/**
 * Protocol-level end-to-end test (no browser): two ws clients through the relay,
 * real HKDF + AES-GCM. Verifies routing by roomId, opaque fan-out, decryptability
 * on the peer, and rejection of an id with a bad checksum.
 */
import { WebSocket } from "ws";
import { deriveRoomKeys, encryptJson, decryptJson, generateSecret } from "../client/src/crypto.js";
import type { PeerUpdate } from "../client/src/types.js";

const URL = process.env.WS_URL ?? "ws://localhost:3000/ws";
const wait = (ms: number) => new Promise((r) => setTimeout(r, ms));
let failures = 0;
const check = (cond: boolean, msg: string) => {
  console.log(`${cond ? "✓" : "✗"} ${msg}`);
  if (!cond) failures++;
};

function open(): Promise<WebSocket> {
  return new Promise((res, rej) => {
    const ws = new WebSocket(URL);
    ws.once("open", () => res(ws));
    ws.once("error", rej);
  });
}

async function main() {
  const secret = generateSecret();
  const { roomId, key } = await deriveRoomKeys(secret);
  check(roomId.length === 32, `roomId is 32 chars (${roomId.length})`);

  const a = await open();
  const bReceived: PeerUpdate[] = [];
  const b = await open();
  b.on("message", async (raw) => {
    const msg = JSON.parse(raw.toString());
    if (msg.t === "peer") {
      const dec = await decryptJson<PeerUpdate>(key, msg.data);
      if (dec) bReceived.push(dec);
    }
  });

  a.send(JSON.stringify({ t: "join", roomId }));
  b.send(JSON.stringify({ t: "join", roomId }));
  await wait(300);

  const loc: PeerUpdate = {
    k: "loc",
    seed: "peerA",
    lat: 52.52,
    lng: 13.405,
    acc: 12,
    hdg: null,
    spd: null,
    at: Date.now(),
  };
  a.send(JSON.stringify({ t: "relay", data: await encryptJson(key, loc) }));
  await wait(300);

  check(bReceived.length === 1, `peer B received exactly one update (${bReceived.length})`);
  const got = bReceived[0];
  check(
    !!got && got.k === "loc" && got.lat === 52.52 && got.lng === 13.405 && got.seed === "peerA",
    "decrypted payload matches what A sent"
  );

  // A must NOT receive its own broadcast (server excludes sender).
  let aGotOwn = false;
  a.on("message", (raw) => {
    if (JSON.parse(raw.toString()).t === "peer") aGotOwn = true;
  });
  a.send(JSON.stringify({ t: "relay", data: await encryptJson(key, loc) }));
  await wait(200);
  check(!aGotOwn, "sender does not receive its own broadcast");

  // Wrong key cannot decrypt (confidentiality).
  const other = await deriveRoomKeys(generateSecret());
  const opaque = await encryptJson(key, loc);
  const bad = await decryptJson<PeerUpdate>(other.key, opaque);
  check(bad === null, "payload does not decrypt under a different room key");

  // Bad-checksum roomId is rejected and the socket is closed.
  const c = await open();
  let rejected = false;
  let closed = false;
  c.on("message", (raw) => {
    if (JSON.parse(raw.toString()).t === "error") rejected = true;
  });
  c.on("close", () => (closed = true));
  const forged = "A".repeat(32); // valid charset + length, invalid checksum
  c.send(JSON.stringify({ t: "join", roomId: forged }));
  await wait(300);
  check(rejected, "forged roomId gets an error");
  check(closed, "forged roomId connection is closed");

  a.close();
  b.close();
  await wait(100);
  console.log(failures === 0 ? "\nALL PASSED" : `\n${failures} FAILED`);
  process.exit(failures === 0 ? 0 : 1);
}

main();
