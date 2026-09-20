/**
 * The "browser side" of the interop check (see scripts/interop-test.sh).
 *
 * Joins a room with the REAL client crypto, broadcasts one known position, and
 * waits to decrypt the native client's. Proves the two implementations agree on
 * the room derivation, the AES-GCM packing and the payload shape — the three
 * things whose divergence is invisible at runtime.
 *
 * Usage: tsx test/interop-web-peer.ts <secret> <wsUrl> <resultFile>
 */
import { writeFileSync } from "node:fs";
import { WebSocket } from "ws";
import { deriveRoomKeys, encryptJson, decryptJson } from "../client/src/crypto.js";
import type { PeerUpdate } from "../client/src/types.js";

const [secret, wsUrl, resultFile] = process.argv.slice(2);
const SELF = "web-peer";
const EXPECT = "app-peer";
const TIMEOUT_MS = 20_000;

const MY_UPDATE: PeerUpdate = {
  k: "loc",
  seed: SELF,
  lat: 52.520008,
  lng: 13.404954,
  acc: 8.5,
  hdg: 275.5,
  spd: 1.75,
  at: 1_700_000_000_123,
};

function finish(result: Record<string, unknown>, code: number): never {
  writeFileSync(resultFile, JSON.stringify(result, null, 2));
  console.log(`[web-peer] ${JSON.stringify(result)}`);
  process.exit(code);
}

async function main(): Promise<void> {
  const { roomId, key } = await deriveRoomKeys(secret);
  const ws = new WebSocket(wsUrl, { headers: { Origin: "https://herebee.app" } });

  const timer = setTimeout(
    () => finish({ ok: false, error: "timed out waiting for the app peer", roomId }, 1),
    TIMEOUT_MS
  );

  const broadcast = async () => ws.send(JSON.stringify({ t: "relay", data: await encryptJson(key, MY_UPDATE) }));

  ws.on("open", async () => {
    ws.send(JSON.stringify({ t: "join", roomId, cid: "web-peer-cid" }));
    await broadcast();
  });

  ws.on("message", async (raw) => {
    const msg = JSON.parse(raw.toString());
    if (msg.t === "request") return void broadcast(); // a peer joined; resend
    if (msg.t !== "peer") return;
    const update = await decryptJson<PeerUpdate>(key, msg.data);
    if (!update || update.seed !== EXPECT) return;
    clearTimeout(timer);
    finish({ ok: true, roomId, decrypted: update }, 0);
  });

  ws.on("error", (err) => finish({ ok: false, error: String(err) }, 1));
}

void main();
