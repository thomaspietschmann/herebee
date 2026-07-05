/**
 * Localizer relay + static host — one Node process, one port.
 *
 * Serves the built client, the self-hosted map assets (a .pmtiles archive with
 * HTTP Range support, plus glyphs/sprites), a /healthz endpoint, and the
 * WebSocket relay. It forwards opaque end-to-end-encrypted blobs and never
 * inspects, logs, or stores their contents, coordinates, names, or client IPs.
 */
import { createServer, type IncomingMessage, type ServerResponse } from "node:http";
import { createReadStream, existsSync, statSync } from "node:fs";
import { extname, join, normalize, resolve } from "node:path";
import { randomBytes } from "node:crypto";
import { WebSocketServer, type WebSocket } from "ws";
import { clientMessageSchema, ROOM_ID_LENGTH } from "../../shared/messages.js";
import { isValidRoomId } from "./roomId.js";
import { type Conn, joinRoom, leaveRoom, relay, send, stats } from "./relay.js";

const PORT = Number(process.env.PORT ?? 3000);
const ROOT = resolve(process.cwd());
const CLIENT_DIST = resolve(process.env.CLIENT_DIST ?? join(ROOT, "client", "dist"));
const ASSETS_DIR = resolve(process.env.ASSETS_DIR ?? join(ROOT, "server", "assets"));
const ALLOWED_ORIGINS = (process.env.ALLOWED_ORIGINS ?? "")
  .split(",")
  .map((s) => s.trim())
  .filter(Boolean);

// --- rate limiting -------------------------------------------------------
const RATE_TOKENS = 10; // burst
const RATE_PER_SEC = 10; // sustained messages / second
const MAX_PAYLOAD = 16 * 1024; // bytes per WS frame
const MAX_CONNS_PER_IP = 40;
const connsPerIp = new Map<string, number>();

function takeToken(conn: Conn): boolean {
  const now = Date.now();
  const elapsed = (now - conn.lastRefill) / 1000;
  conn.bucket = Math.min(RATE_TOKENS, conn.bucket + elapsed * RATE_PER_SEC);
  conn.lastRefill = now;
  if (conn.bucket < 1) return false;
  conn.bucket -= 1;
  return true;
}

// --- static file serving -------------------------------------------------
const MIME: Record<string, string> = {
  ".html": "text/html; charset=utf-8",
  ".js": "text/javascript; charset=utf-8",
  ".css": "text/css; charset=utf-8",
  ".json": "application/json; charset=utf-8",
  ".svg": "image/svg+xml",
  ".png": "image/png",
  ".webp": "image/webp",
  ".pbf": "application/x-protobuf",
  ".pmtiles": "application/octet-stream",
  ".woff2": "font/woff2",
};

function securityHeaders(res: ServerResponse): void {
  res.setHeader(
    "Content-Security-Policy",
    [
      "default-src 'self'",
      "script-src 'self'",
      "style-src 'self' 'unsafe-inline'",
      "img-src 'self' data: blob:",
      "font-src 'self' data:",
      "worker-src 'self' blob:",
      "connect-src 'self' ws: wss:",
      "base-uri 'self'",
      "form-action 'self'",
      "frame-ancestors 'none'",
    ].join("; ")
  );
  res.setHeader("Permissions-Policy", "geolocation=(self), microphone=(), camera=()");
  res.setHeader("Referrer-Policy", "no-referrer");
  res.setHeader("X-Content-Type-Options", "nosniff");
  res.setHeader("Cross-Origin-Opener-Policy", "same-origin");
  res.setHeader("Strict-Transport-Security", "max-age=31536000; includeSubDomains");
}

/** Resolve a request path inside a base dir, refusing traversal. */
function safeJoin(base: string, urlPath: string): string | null {
  const clean = normalize(decodeURIComponent(urlPath)).replace(/^(\.\.[/\\])+/, "");
  const full = resolve(base, "." + (clean.startsWith("/") ? clean : "/" + clean));
  return full.startsWith(base) ? full : null;
}

function serveFile(req: IncomingMessage, res: ServerResponse, filePath: string, immutable = false): void {
  let st;
  try {
    st = statSync(filePath);
    if (!st.isFile()) throw new Error("not a file");
  } catch {
    res.writeHead(404).end("Not found");
    return;
  }
  const type = MIME[extname(filePath).toLowerCase()] ?? "application/octet-stream";
  res.setHeader("Content-Type", type);
  res.setHeader("Accept-Ranges", "bytes");
  if (immutable) res.setHeader("Cache-Control", "public, max-age=31536000, immutable");

  // Range support — required for MapLibre reading .pmtiles via byte ranges.
  const range = req.headers.range;
  if (range) {
    const m = /^bytes=(\d*)-(\d*)$/.exec(range);
    if (m) {
      const total = st.size;
      let start = m[1] ? parseInt(m[1], 10) : 0;
      let end = m[2] ? parseInt(m[2], 10) : total - 1;
      if (Number.isNaN(start) || Number.isNaN(end) || start > end || end >= total) {
        res.writeHead(416, { "Content-Range": `bytes */${total}` }).end();
        return;
      }
      res.writeHead(206, {
        "Content-Range": `bytes ${start}-${end}/${total}`,
        "Content-Length": end - start + 1,
      });
      createReadStream(filePath, { start, end }).pipe(res);
      return;
    }
  }
  res.setHeader("Content-Length", st.size);
  createReadStream(filePath).pipe(res);
}

const httpServer = createServer((req, res) => {
  securityHeaders(res);
  const url = new URL(req.url ?? "/", "http://localhost");
  const path = url.pathname;

  if (path === "/healthz") {
    const s = stats();
    res.writeHead(200, { "Content-Type": "application/json" });
    res.end(JSON.stringify({ ok: true, ...s }));
    return;
  }

  // Self-hosted map assets (tiles, glyphs, sprites) — immutable, cacheable.
  if (path.startsWith("/tiles/") || path.startsWith("/basemaps/")) {
    const file = safeJoin(ASSETS_DIR, path);
    if (!file) return void res.writeHead(400).end("Bad path");
    serveFile(req, res, file, true);
    return;
  }

  // Static client. SPA-style: unknown non-file paths fall back to index.html.
  const candidate = safeJoin(CLIENT_DIST, path === "/" ? "/index.html" : path);
  if (candidate && existsSync(candidate) && statSync(candidate).isFile()) {
    serveFile(req, res, candidate, extname(candidate) !== ".html");
    return;
  }
  const indexHtml = join(CLIENT_DIST, "index.html");
  if (existsSync(indexHtml)) {
    serveFile(req, res, indexHtml, false);
    return;
  }
  res.writeHead(404).end("Not found");
});

// --- WebSocket relay -----------------------------------------------------
const wss = new WebSocketServer({ noServer: true, maxPayload: MAX_PAYLOAD });

function originAllowed(req: IncomingMessage): boolean {
  const origin = req.headers.origin;
  if (!origin) return true; // non-browser clients / same-origin fetches without Origin
  if (ALLOWED_ORIGINS.length === 0) {
    // Dev/default: accept same-host and localhost.
    try {
      const o = new URL(origin);
      const host = (req.headers.host ?? "").split(":")[0];
      return o.hostname === host || o.hostname === "localhost" || o.hostname === "127.0.0.1";
    } catch {
      return false;
    }
  }
  return ALLOWED_ORIGINS.includes(origin);
}

function clientIp(req: IncomingMessage): string {
  // Used ONLY for a per-IP connection cap, never logged or stored.
  const fwd = req.headers["x-forwarded-for"];
  if (typeof fwd === "string" && fwd.length) return fwd.split(",")[0].trim();
  return req.socket.remoteAddress ?? "unknown";
}

httpServer.on("upgrade", (req, socket, head) => {
  if (new URL(req.url ?? "/", "http://localhost").pathname !== "/ws" || !originAllowed(req)) {
    socket.destroy();
    return;
  }
  const ip = clientIp(req);
  const count = connsPerIp.get(ip) ?? 0;
  if (count >= MAX_CONNS_PER_IP) {
    socket.destroy();
    return;
  }
  wss.handleUpgrade(req, socket, head, (ws) => {
    connsPerIp.set(ip, count + 1);
    ws.once("close", () => {
      const c = (connsPerIp.get(ip) ?? 1) - 1;
      if (c <= 0) connsPerIp.delete(ip);
      else connsPerIp.set(ip, c);
    });
    wss.emit("connection", ws, req);
  });
});

interface AliveWs extends WebSocket {
  isAlive?: boolean;
}

wss.on("connection", (ws: AliveWs) => {
  ws.isAlive = true;
  ws.on("pong", () => {
    ws.isAlive = true;
  });

  const conn: Conn = {
    id: randomBytes(9).toString("base64url"),
    ws,
    roomId: null,
    bucket: RATE_TOKENS,
    lastRefill: Date.now(),
    alive: true,
    lastData: null,
  };

  ws.on("message", (raw) => {
    if (!takeToken(conn)) return; // silently drop over-rate frames
    let parsed;
    try {
      parsed = clientMessageSchema.safeParse(JSON.parse(raw.toString()));
    } catch {
      return;
    }
    if (!parsed.success) return;
    const msg = parsed.data;
    if (msg.t === "join") {
      if (conn.roomId) return; // already joined
      if (msg.roomId.length !== ROOM_ID_LENGTH || !isValidRoomId(msg.roomId)) {
        send(conn, { t: "error", reason: "invalid-room" });
        ws.close(1008, "invalid-room");
        return;
      }
      joinRoom(conn, msg.roomId);
    } else if (msg.t === "relay") {
      if (!conn.roomId) return;
      relay(conn, msg.data);
    }
  });

  ws.on("close", () => leaveRoom(conn));
  ws.on("error", () => leaveRoom(conn));
});

// Heartbeat: reap dead sockets (leaveRoom runs via their "close" handler).
const heartbeat = setInterval(() => {
  for (const ws of wss.clients as Set<AliveWs>) {
    if (ws.isAlive === false) {
      ws.terminate();
      continue;
    }
    ws.isAlive = false;
    ws.ping();
  }
}, 30_000);

httpServer.on("close", () => clearInterval(heartbeat));

httpServer.listen(PORT, () => {
  // Intentionally minimal, no request/IP logging.
  console.log(`localizer relay listening on :${PORT}`);
});
