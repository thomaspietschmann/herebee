/**
 * A stand-in room participant for development.
 *
 * Joins a room with the REAL client crypto and walks a position around, so the
 * map, the markers and the freshness tiers can be exercised without two phones
 * and two people. Also useful for the native app before it can share a location
 * of its own.
 *
 * With --watch-only it broadcasts nothing and instead logs every position it
 * decrypts, with arrival times. That is how the background-location requirement
 * is actually verified: lock the phone, watch this keep printing.
 *
 * Usage: tsx scripts/fake-peer.ts [--ws ws://127.0.0.1:3100/ws] [--secret <s>]
 *                                 [--seed dev-peer] [--lat 52.52] [--lng 13.405]
 *                                 [--watch-only]
 * Prints the room link to open in a browser or pass to the app.
 */
import { WebSocket } from "ws";
import { decryptJson, deriveRoomKeys, encryptJson, generateSecret } from "../client/src/crypto.js";
import type { PeerUpdate } from "../client/src/types.js";

function arg(name: string, fallback: string): string {
  const i = process.argv.indexOf(`--${name}`);
  return i >= 0 && process.argv[i + 1] ? process.argv[i + 1] : fallback;
}

const wsUrl = arg("ws", "ws://127.0.0.1:3100/ws");
const secret = arg("secret", generateSecret());
const seed = arg("seed", "dev-peer");
const originHeader = arg("origin", "https://herebee.app");
let lat = Number(arg("lat", "52.52"));
let lng = Number(arg("lng", "13.405"));
const watchOnly = process.argv.includes("--watch-only");

// One update per second, matching the client's outbound throttle.
const STEP_MS = 1000;
const SPEED_MS = 1.6; // slow walk, above the arrow threshold

async function main(): Promise<void> {
  const { roomId, key } = await deriveRoomKeys(secret);
  console.log(`room secret : ${secret}`);
  console.log(`room id     : ${roomId}`);
  console.log(`browser     : http://127.0.0.1:3100/r/#${secret}`);
  console.log(`app         : --dart-define=HEREBEE_SECRET=${secret}`);

  const ws = new WebSocket(wsUrl, { headers: { Origin: originHeader } });
  let heading = 90;

  const broadcast = async () => {
    // Walk east, drifting slightly, so the heading arrow and the camera-follow
    // behaviour have something to react to.
    heading = (heading + (Math.random() * 10 - 5) + 360) % 360;
    const rad = (heading * Math.PI) / 180;
    const metres = SPEED_MS * (STEP_MS / 1000);
    lat += (metres * Math.cos(rad)) / 111_320;
    lng += (metres * Math.sin(rad)) / (111_320 * Math.cos((lat * Math.PI) / 180));
    const update: PeerUpdate = {
      k: "loc",
      seed,
      lat,
      lng,
      acc: 8,
      hdg: heading,
      spd: SPEED_MS,
      at: Date.now(),
    };
    ws.send(JSON.stringify({ t: "relay", data: await encryptJson(key, update) }));
  };

  ws.on("open", async () => {
    ws.send(JSON.stringify({ t: "join", roomId, cid: `fake-${seed}` }));
    if (watchOnly) {
      console.log(`\n✓ watching only. Every decrypted position is logged below.`);
      return;
    }
    await broadcast();
    setInterval(() => void broadcast(), STEP_MS);
    console.log(`\n✓ "${seed}" is walking. Ctrl-C to stop.`);
  });
  ws.on("message", async (raw) => {
    const msg = JSON.parse(raw.toString());
    if (msg.t === "request" && !watchOnly) void broadcast();
    if (msg.t === "presence") console.log(`  presence: ${msg.n}`);
    if (msg.t === "error") console.error(`  relay error: ${msg.reason}`);
    if (msg.t === "peer") {
      const u = await decryptJson<PeerUpdate>(key, msg.data);
      if (!u) return;
      const stamp = new Date().toISOString().slice(11, 19);
      if (u.k === "stop") console.log(`  [${stamp}] ${u.seed} stopped sharing`);
      else console.log(`  [${stamp}] ${u.seed} @ ${u.lat.toFixed(5)},${u.lng.toFixed(5)} acc=${u.acc ?? "-"}`);
    }
  });
  ws.on("close", () => {
    console.error("socket closed");
    process.exit(1);
  });
  ws.on("error", (e) => {
    console.error(String(e));
    process.exit(1);
  });
}

void main();
