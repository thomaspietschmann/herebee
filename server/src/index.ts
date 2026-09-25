/**
 * Localizer relay + static host — one Node process, one port.
 *
 * Serves the built client, the self-hosted map assets (a .pmtiles archive with
 * HTTP Range support, plus glyphs/sprites), a /healthz endpoint, and the
 * WebSocket relay. It forwards opaque end-to-end-encrypted blobs and never
 * inspects, logs, or stores their contents, coordinates, names, or client IPs.
 */
import { createServer, type IncomingMessage, type ServerResponse } from "node:http";
import { createReadStream, existsSync, readFileSync, statSync } from "node:fs";
import { extname, join, normalize, resolve, sep } from "node:path";
import { randomBytes } from "node:crypto";
import { WebSocketServer, type WebSocket } from "ws";
import { clientMessageSchema, ROOM_ID_LENGTH } from "../../shared/messages.js";
import { negotiate, OG } from "../../shared/og.js";
import { isValidRoomId } from "./roomId.js";
import { type Conn, joinRoom, leaveRoom, relay, send } from "./relay.js";

const PORT = Number(process.env.PORT ?? 3000);
const ROOT = resolve(process.cwd());
const CLIENT_DIST = resolve(process.env.CLIENT_DIST ?? join(ROOT, "client", "dist"));
const ASSETS_DIR = resolve(process.env.ASSETS_DIR ?? join(ROOT, "server", "assets"));
const csv = (v: string | undefined): string[] =>
  (v ?? "")
    .split(",")
    .map((s) => s.trim())
    .filter(Boolean);

const ALLOWED_ORIGINS = csv(process.env.ALLOWED_ORIGINS);

// Absolute origin handed to native clients in the generated map style. Set it in
// production (e.g. https://herebee.app); left empty it is derived per request,
// which is what dev wants.
const PUBLIC_ORIGIN = (process.env.PUBLIC_ORIGIN ?? "").trim().replace(/\/+$/, "");

// Deep-link association files. Each is served only when its env is present, so a
// half-configured deployment serves nothing rather than something wrong.
// APPLE_APP_IDS: comma list of "TEAMID.bundleId". ANDROID_CERT_SHA256: comma list
// of colon-separated SHA-256 signing fingerprints (debug, upload, Play App Signing).
const APPLE_APP_IDS = csv(process.env.APPLE_APP_IDS);
const ANDROID_PACKAGE = (process.env.ANDROID_PACKAGE ?? "").trim();
const ANDROID_CERT_SHA256 = csv(process.env.ANDROID_CERT_SHA256);

/** Origin the native apps use on the WebSocket upgrade. See originAllowed(). */
const APP_ORIGIN = "app://herebee";

/** UI languages with a generated map style. Keep in sync with client/src/i18n.ts. */
const STYLE_LANGS = new Set(["de", "en", "es", "it", "fr", "pt"]);

/** Placeholder written by scripts/gen-style.ts, replaced per request. */
const ORIGIN_PLACEHOLDER = "__HEREBEE_ORIGIN__";

// --- rate limiting -------------------------------------------------------
const RATE_TOKENS = 10; // burst
const RATE_PER_SEC = 10; // sustained messages / second
const MAX_PAYLOAD = 16 * 1024; // bytes per WS frame
const MAX_CONNS_PER_IP = 40;
const MAX_TOTAL_CONNS = Number(process.env.MAX_CONNS ?? 10_000); // global socket ceiling
const connsPerIp = new Map<string, number>();

// Number of trusted reverse-proxy hops in front of this process. 0 (default,
// safe for dev/direct) means "ignore X-Forwarded-For and use the socket IP".
// Behind exactly one proxy (Traefik/Coolify) set TRUSTED_PROXY_HOPS=1 so the
// per-IP cap keys on the real client IP instead of a spoofable XFF entry.
const TRUSTED_PROXY_HOPS = Math.max(0, Number(process.env.TRUSTED_PROXY_HOPS ?? 0));

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
      // Same-origin only — includes the same-host wss:// upgrade for /ws. Kept
      // tight so a compromised dependency can't exfiltrate the fragment secret
      // to a foreign WebSocket host despite script-src 'self'.
      "connect-src 'self'",
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
  // A malformed percent-escape (e.g. "/%", "/%zz") makes decodeURIComponent throw
  // a URIError. Guard it here: without this the throw propagates out of the HTTP
  // request handler as an uncaught exception and takes the whole process down.
  let decoded: string;
  try {
    decoded = decodeURIComponent(urlPath);
  } catch {
    return null;
  }
  const clean = normalize(decoded).replace(/^(\.\.[/\\])+/, "");
  const full = resolve(base, "." + (clean.startsWith("/") ? clean : "/" + clean));
  // Require a real path-separator boundary so "/base" can't match a sibling like
  // "/base-evil"; the resolved base itself is also valid (a request for "/").
  return full === base || full.startsWith(base + sep) ? full : null;
}

/**
 * How long a served file may be reused without asking again.
 *  - "immutable": content-hashed build output, never changes under its URL.
 *  - "week": map assets. Their URLs are fixed but the files get replaced when
 *    the basemap is rebuilt, so caches must come back eventually; the ETag
 *    makes that a cheap 304, and If-Range keeps stale byte ranges of an old
 *    archive from being stitched onto a new one.
 *  - "none": no Cache-Control at all.
 */
type CachePolicy = "immutable" | "week" | "none";
const CACHE_CONTROL: Record<CachePolicy, string | null> = {
  immutable: "public, max-age=31536000, immutable",
  week: "public, max-age=604800",
  none: null,
};

function serveFile(req: IncomingMessage, res: ServerResponse, filePath: string, cache: CachePolicy = "none"): void {
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
  const cacheControl = CACHE_CONTROL[cache];
  if (cacheControl) res.setHeader("Cache-Control", cacheControl);
  // Strong validator from size + mtime: replacing the file changes it, and it
  // must be strong for If-Range to accept it.
  const etag = `"${st.size.toString(36)}-${Math.floor(st.mtimeMs).toString(36)}"`;
  res.setHeader("ETag", etag);
  const lastModified = st.mtime.toUTCString();
  res.setHeader("Last-Modified", lastModified);

  const inm = req.headers["if-none-match"];
  if (inm && inm.split(",").some((t) => t.trim() === etag || t.trim() === "*")) {
    res.writeHead(304).end();
    return;
  }

  // Range support — required for MapLibre reading .pmtiles via byte ranges.
  // A range is only valid against the version it was taken from: if If-Range
  // names another one, the file changed and the client gets all of it instead.
  const ifRange = req.headers["if-range"];
  const range = ifRange && ifRange !== etag && ifRange !== lastModified ? undefined : req.headers.range;
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

// --- native app endpoints -------------------------------------------------
/**
 * Absolute origin to hand out in generated documents (the map style). Prefer the
 * explicit PUBLIC_ORIGIN; otherwise reconstruct it from the request so dev
 * (http://localhost:3000) and any future domain work without a rebuild.
 */
function publicOrigin(req: IncomingMessage): string {
  if (PUBLIC_ORIGIN) return PUBLIC_ORIGIN;
  const host = req.headers.host ?? `localhost:${PORT}`;
  // Only believe the scheme header when a trusted proxy actually sits in front.
  // Unlike X-Forwarded-For (where the LAST entry is the trustworthy one), the
  // FIRST X-Forwarded-Proto entry is the scheme the client originally used.
  const fwd = TRUSTED_PROXY_HOPS > 0 ? req.headers["x-forwarded-proto"] : undefined;
  const proto = typeof fwd === "string" && fwd.length ? fwd.split(",")[0].trim() : "http";
  return `${proto}://${host}`;
}

function serveJson(res: ServerResponse, value: unknown, cacheSeconds = 0): void {
  const body = Buffer.from(JSON.stringify(value), "utf8");
  res.setHeader("Content-Type", "application/json");
  if (cacheSeconds > 0) res.setHeader("Cache-Control", `public, max-age=${cacheSeconds}`);
  res.setHeader("Content-Length", body.length);
  res.end(body);
}

/**
 * The generated MapLibre style for the native apps (see scripts/gen-style.ts).
 * Files on disk carry ORIGIN_PLACEHOLDER; the real origin is substituted here so
 * one build serves every domain. Cached per language in its raw form.
 */
const styleCache = new Map<string, string>();

function serveStyle(req: IncomingMessage, res: ServerResponse, lang: string): void {
  let raw = styleCache.get(lang);
  if (raw === undefined) {
    try {
      raw = readFileSync(join(CLIENT_DIST, "style", `${lang}.json`), "utf8");
    } catch {
      // Not built yet (e.g. `npm run start` without `npm run build`).
      res.writeHead(404).end("Not found");
      return;
    }
    styleCache.set(lang, raw);
  }
  const body = Buffer.from(raw.split(ORIGIN_PLACEHOLDER).join(publicOrigin(req)), "utf8");
  res.setHeader("Content-Type", "application/json");
  res.setHeader("Cache-Control", "public, max-age=300");
  res.setHeader("Vary", "Host, X-Forwarded-Proto");
  res.setHeader("Content-Length", body.length);
  res.end(body);
}

/**
 * The /.well-known/ namespace. Apple's CDN and Google's verifier fetch the two
 * association documents to confirm this domain may open the apps; they carry no
 * user data, only the app id and signing fingerprints, which are public by
 * nature.
 *
 * This owns the WHOLE namespace: anything unrecognised gets a 404 rather than
 * falling through to the SPA. A verifier that receives index.html instead of
 * JSON fails in a way that is very hard to debug, and well-known paths are a
 * machine-readable namespace where an HTML app shell is never a valid answer.
 * Real static files under /.well-known/ (should any ever be added to
 * client/public) still win — they are checked before the 404.
 */
function serveWellKnown(req: IncomingMessage, res: ServerResponse, path: string): void {
  if (path === "/.well-known/apple-app-site-association") {
    if (APPLE_APP_IDS.length === 0) {
      res.writeHead(404).end("Not found");
      return;
    }
    // Room links only. Everything else stays in the browser, which is the point
    // of the web app: no install required.
    serveJson(
      res,
      { applinks: { details: [{ appIDs: APPLE_APP_IDS, components: [{ "/": "/r/*", comment: "room link" }] }] } },
      300
    );
    return;
  }
  if (path === "/.well-known/assetlinks.json") {
    if (!ANDROID_PACKAGE || ANDROID_CERT_SHA256.length === 0) {
      res.writeHead(404).end("Not found");
      return;
    }
    serveJson(
      res,
      [
        {
          relation: ["delegate_permission/common.handle_all_urls"],
          target: {
            namespace: "android_app",
            package_name: ANDROID_PACKAGE,
            sha256_cert_fingerprints: ANDROID_CERT_SHA256,
          },
        },
      ],
      300
    );
    return;
  }

  // A real file, if one was ever placed in client/public/.well-known/.
  const file = safeJoin(CLIENT_DIST, path);
  if (file && existsSync(file) && statSync(file).isFile()) {
    serveFile(req, res, file);
    return;
  }
  res.writeHead(404).end("Not found");
}

// --- OG/Twitter meta localization -----------------------------------------
// Social crawlers don't run JS, so the client's runtime i18n never reaches
// them — only what this server sends on the initial HTML response does. The
// English strings baked into index.html (see shared/og.ts's `OG.en`) are the
// source of truth; for any other negotiated language we substitute the exact
// matching substrings. `en` (and anything unmatched, per `negotiate`'s
// fallback) is served byte-for-byte unchanged.
let indexHtmlCache: string | null = null;

function localizeHtml(html: string, lang: keyof typeof OG): string {
  if (lang === "en") return html;
  const src = OG.en;
  const dst = OG[lang];
  return html
    .split(src.title)
    .join(dst.title)
    .split(src.description)
    .join(dst.description)
    .split(src.ogDescription)
    .join(dst.ogDescription)
    .split(src.imageAlt)
    .join(dst.imageAlt)
    .split(`content="${src.ogLocale}"`)
    .join(`content="${dst.ogLocale}"`)
    .split(`lang="${src.htmlLang}"`)
    .join(`lang="${dst.htmlLang}"`);
}

function serveIndexHtml(req: IncomingMessage, res: ServerResponse, filePath: string): void {
  let html = indexHtmlCache;
  if (html === null) {
    try {
      html = readFileSync(filePath, "utf8");
    } catch {
      res.writeHead(404).end("Not found");
      return;
    }
    indexHtmlCache = html;
  }
  const lang = negotiate(req.headers["accept-language"]);
  const body = Buffer.from(localizeHtml(html, lang), "utf8");
  res.setHeader("Content-Type", "text/html; charset=utf-8");
  res.setHeader("Vary", "Accept-Language");
  res.setHeader("Content-Length", body.length);
  res.end(body);
}

const httpServer = createServer((req, res) => {
  securityHeaders(res);
  const url = new URL(req.url ?? "/", "http://localhost");
  const path = url.pathname;

  if (path === "/healthz") {
    // Liveness only — deliberately no room/connection counts, so occupancy of the
    // service isn't exposed to anonymous pollers.
    res.writeHead(200, { "Content-Type": "application/json" });
    res.end(JSON.stringify({ ok: true }));
    return;
  }

  // Deep-link association files for the native apps. Must come before the static
  // handler, which would otherwise fall through to index.html and hand Apple /
  // Google an HTML page (a silent, hard-to-debug verification failure).
  if (path.startsWith("/.well-known/")) {
    serveWellKnown(req, res, path);
    return;
  }

  // Generated map style for the native apps: /style/{lang}.json. Handled here
  // rather than as a plain static file because the origin is substituted per
  // request (the file on disk holds a placeholder).
  if (path.startsWith("/style/") && path.endsWith(".json")) {
    const lang = path.slice("/style/".length, -".json".length);
    if (STYLE_LANGS.has(lang)) {
      serveStyle(req, res, lang);
      return;
    }
    res.writeHead(404).end("Not found");
    return;
  }

  // Self-hosted map assets (tiles, glyphs, sprites): cached for a week, then revalidated.
  if (path.startsWith("/tiles/") || path.startsWith("/basemaps/")) {
    const file = safeJoin(ASSETS_DIR, path);
    if (!file) return void res.writeHead(400).end("Bad path");
    serveFile(req, res, file, "week");
    return;
  }

  // Static client. SPA-style: unknown non-file paths fall back to index.html.
  // index.html is special-cased to localize its OG/Twitter meta (see above);
  // every other file is served as-is.
  const candidate = safeJoin(CLIENT_DIST, path === "/" ? "/index.html" : path);
  if (candidate && existsSync(candidate) && statSync(candidate).isFile()) {
    if (extname(candidate) === ".html") serveIndexHtml(req, res, candidate);
    else serveFile(req, res, candidate, "immutable");
    return;
  }
  const indexHtml = join(CLIENT_DIST, "index.html");
  if (existsSync(indexHtml)) {
    serveIndexHtml(req, res, indexHtml);
    return;
  }
  res.writeHead(404).end("Not found");
});

// --- WebSocket relay -----------------------------------------------------
const wss = new WebSocketServer({ noServer: true, maxPayload: MAX_PAYLOAD });

function originAllowed(req: IncomingMessage): boolean {
  const origin = req.headers.origin;

  // Native apps. The Origin check exists to stop a FOREIGN WEB PAGE from opening
  // a socket in a visitor's browser — it is CSRF hygiene, not authentication
  // (nothing here is authenticated: the room secret never reaches the server, and
  // any non-browser client can set whatever Origin it likes). Native clients are
  // not browsers, so they announce themselves explicitly and the operator opts in
  // by listing APP_ORIGIN in ALLOWED_ORIGINS. Some platforms refuse to let a
  // WebSocket set `Origin`, hence the X-HereBee-Client fallback for that case.
  const appClient = req.headers["x-herebee-client"];
  if (origin === APP_ORIGIN || (!origin && typeof appClient === "string" && appClient.length > 0)) {
    return ALLOWED_ORIGINS.length === 0 || ALLOWED_ORIGINS.includes(APP_ORIGIN);
  }

  // In production (ALLOWED_ORIGINS set) require a browser Origin so a headless
  // client can't skip the check by omitting the header. In dev (no list) allow it.
  if (!origin) return ALLOWED_ORIGINS.length === 0;
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
  // Used ONLY for a per-IP connection cap, never logged or stored. The leftmost
  // X-Forwarded-For entry is client-controlled and spoofable, so we only trust
  // XFF when a proxy hop count is configured and then take the entry our own
  // trusted proxy appended (the Nth from the right), not the client's claim.
  if (TRUSTED_PROXY_HOPS > 0) {
    const fwd = req.headers["x-forwarded-for"];
    if (typeof fwd === "string" && fwd.length) {
      const parts = fwd.split(",").map((s) => s.trim()).filter(Boolean);
      const idx = parts.length - TRUSTED_PROXY_HOPS;
      if (idx >= 0 && idx < parts.length) return parts[idx];
    }
  }
  return req.socket.remoteAddress ?? "unknown";
}

httpServer.on("upgrade", (req, socket, head) => {
  if (new URL(req.url ?? "/", "http://localhost").pathname !== "/ws" || !originAllowed(req)) {
    socket.destroy();
    return;
  }
  if (wss.clients.size >= MAX_TOTAL_CONNS) {
    socket.destroy(); // global ceiling — protects against overall socket exhaustion
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
    cid: null,
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
      joinRoom(conn, msg.roomId, msg.cid);
    } else if (msg.t === "relay") {
      if (!conn.roomId) return;
      relay(conn, msg.data);
    } else if (msg.t === "ping") {
      send(conn, { t: "pong" }); // liveness reply so the client can detect a dead link
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
}, 20_000);

httpServer.on("close", () => clearInterval(heartbeat));

// Last-resort safety net: a single malformed request must never take the relay
// down and drop every live room. We log only the error itself (no request data,
// no IPs) and keep serving.
process.on("uncaughtException", (err) => {
  console.error("uncaughtException:", err?.message ?? err);
});
process.on("unhandledRejection", (reason) => {
  console.error("unhandledRejection:", reason instanceof Error ? reason.message : reason);
});

httpServer.listen(PORT, () => {
  // Intentionally minimal, no request/IP logging.
  console.log(`localizer relay listening on :${PORT}`);
});
