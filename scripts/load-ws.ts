import { WebSocket } from "ws";
import { deriveRoomKeys, encryptJson, generateSecret } from "../client/src/crypto.js";
import type { PeerUpdate } from "../client/src/types.js";

function arg(name: string, fallback: string): string {
  const i = process.argv.indexOf(`--${name}`);
  return i >= 0 && process.argv[i + 1] ? process.argv[i + 1] : fallback;
}

if (process.argv.includes("--help")) {
  console.log(`Usage: tsx scripts/load-ws.ts [--ws ws://127.0.0.1:3100/ws] [--origin https://herebee.app]
                          [--users 200] [--room-size 4] [--ramp 50] [--interval 1000] [--duration 120]

  --users      simulated participants in total
  --room-size  participants per room
  --ramp       new connections per second
  --interval   ms between position updates per participant
  --duration   seconds to hold full load after ramp-up`);
  process.exit(0);
}

const wsUrl = arg("ws", "ws://127.0.0.1:3100/ws");
const origin = arg("origin", "https://herebee.app");
const users = Number(arg("users", "200"));
const roomSize = Number(arg("room-size", "4"));
const ramp = Number(arg("ramp", "50"));
const interval = Number(arg("interval", "1000"));
const duration = Number(arg("duration", "120"));

type Room = { roomId: string; key: CryptoKey; sent: Map<string, number> };

const stats = {
  open: 0,
  failed: 0,
  closed: 0,
  errors: 0,
  sent: 0,
  received: 0,
  latencies: [] as number[],
  allLatencies: [] as number[],
};
const sockets: WebSocket[] = [];
const timers: NodeJS.Timeout[] = [];

function percentile(sorted: number[], p: number): number {
  if (!sorted.length) return NaN;
  return sorted[Math.min(sorted.length - 1, Math.floor((p / 100) * sorted.length))];
}

function latencyLine(values: number[]): string {
  const s = [...values].sort((a, b) => a - b);
  return `p50 ${percentile(s, 50)}ms  p95 ${percentile(s, 95)}ms  p99 ${percentile(s, 99)}ms  max ${s.at(-1) ?? NaN}ms`;
}

function startUser(room: Room, index: number): void {
  const ws = new WebSocket(wsUrl, { headers: { Origin: origin } });
  sockets.push(ws);
  let lat = 52.52 + Math.random() * 0.05;
  let lng = 13.405 + Math.random() * 0.05;
  let opened = false;

  const broadcast = async () => {
    if (ws.readyState !== WebSocket.OPEN) return;
    lat += (Math.random() - 0.5) * 0.0001;
    lng += (Math.random() - 0.5) * 0.0001;
    const update: PeerUpdate = { k: "loc", seed: `load-${index}`, lat, lng, acc: 8, hdg: 90, spd: 1.4, at: Date.now() };
    const data = await encryptJson(room.key, update);
    room.sent.set(data, Date.now());
    ws.send(JSON.stringify({ t: "relay", data }));
    stats.sent += 1;
  };

  ws.on("open", () => {
    opened = true;
    stats.open += 1;
    ws.send(JSON.stringify({ t: "join", roomId: room.roomId, cid: `load-${index}` }));
    setTimeout(() => {
      void broadcast();
      timers.push(setInterval(() => void broadcast(), interval));
    }, Math.random() * interval);
    timers.push(setInterval(() => ws.readyState === WebSocket.OPEN && ws.send('{"t":"ping"}'), 20_000));
  });
  ws.on("message", (raw) => {
    const msg = JSON.parse(raw.toString());
    if (msg.t === "peer") {
      stats.received += 1;
      const sentAt = room.sent.get(msg.data);
      if (sentAt !== undefined) {
        const ms = Date.now() - sentAt;
        stats.latencies.push(ms);
        stats.allLatencies.push(ms);
      }
    } else if (msg.t === "request") {
      void broadcast();
    } else if (msg.t === "error") {
      stats.errors += 1;
    }
  });
  ws.on("close", () => {
    if (opened) {
      stats.open -= 1;
      stats.closed += 1;
    }
  });
  ws.on("error", () => {
    if (!opened) stats.failed += 1;
  });
}

async function main(): Promise<void> {
  const roomCount = Math.ceil(users / roomSize);
  const rooms: Room[] = [];
  for (let i = 0; i < roomCount; i++) {
    const { roomId, key } = await deriveRoomKeys(generateSecret());
    rooms.push({ roomId, key, sent: new Map() });
  }
  console.log(`${users} users in ${roomCount} rooms of ${roomSize}, ramp ${ramp}/s, update every ${interval}ms → ${wsUrl}`);

  const startedAt = Date.now();
  let lastSent = 0;
  let lastReceived = 0;
  const report = setInterval(() => {
    const secs = Math.round((Date.now() - startedAt) / 1000);
    const sentRate = (stats.sent - lastSent) / 5;
    const recvRate = (stats.received - lastReceived) / 5;
    lastSent = stats.sent;
    lastReceived = stats.received;
    console.log(
      `[${String(secs).padStart(4)}s] open ${stats.open}  failed ${stats.failed}  dropped ${stats.closed}  errors ${stats.errors}  ` +
        `out ${sentRate.toFixed(0)}/s  in ${recvRate.toFixed(0)}/s  ${latencyLine(stats.latencies)}`,
    );
    stats.latencies = [];
    const cutoff = Date.now() - 30_000;
    for (const room of rooms) {
      for (const [data, at] of room.sent) {
        if (at < cutoff) room.sent.delete(data);
        else break;
      }
    }
  }, 5000);

  for (let i = 0; i < users; i++) {
    startUser(rooms[Math.floor(i / roomSize)], i);
    await new Promise((r) => setTimeout(r, 1000 / ramp));
  }
  console.log(`ramp-up done after ${Math.round((Date.now() - startedAt) / 1000)}s, holding ${duration}s`);
  await new Promise((r) => setTimeout(r, duration * 1000));

  clearInterval(report);
  for (const t of timers) clearInterval(t);
  const expected = stats.sent * (roomSize - 1);
  console.log(
    `\nsummary: target ${users}, open ${stats.open}, failed ${stats.failed}, dropped ${stats.closed}, errors ${stats.errors}\n` +
      `sent ${stats.sent}, received ${stats.received} of ~${expected} expected (${((stats.received / expected) * 100).toFixed(1)}%)\n` +
      `latency ${latencyLine(stats.allLatencies)}`,
  );
  for (const ws of sockets) ws.close();
  setTimeout(() => process.exit(0), 1000);
}

void main();
