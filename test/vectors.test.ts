/**
 * Asserts the web code still reproduces the committed shared/vectors.json.
 *
 * This is the drift alarm. The native apps test against the SAME file, so if a
 * refactor here silently changes a derived roomId, a PRNG value or a bee's SVG,
 * the phones would join different rooms / draw different bees than the browser.
 * Failing here means: either the change was a mistake, or it is intentional AND
 * every client must ship the new behaviour at the same time (regenerate with
 * `npm run vectors` and treat it as a protocol break).
 *
 * Run: npm run test:vectors  (no server needed)
 */
import { readFileSync } from "node:fs";
import { createHash } from "node:crypto";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

import { b64urlToBytes, decryptJson, deriveRoomKeys, encryptJson } from "../client/src/crypto.js";
import { cyrb53, mulberry32 } from "../client/src/rng.js";
import { HUE_PALETTE, creatureSvg, hslToCss, hueFromIndex, hueFromSeed } from "../client/src/avatar.js";
import { englishName, germanName, sanitizeSharedName } from "../client/src/names.js";
import { isValidRoomId } from "../server/src/roomId.js";

const HERE = dirname(fileURLToPath(import.meta.url));
const vectors = JSON.parse(readFileSync(join(HERE, "..", "shared", "vectors.json"), "utf8"));

let failures = 0;
let checks = 0;
const check = (cond: boolean, msg: string): void => {
  checks++;
  if (!cond) {
    failures++;
    console.log(`✗ ${msg}`);
  }
};
const sha256Hex = (s: string) => createHash("sha256").update(s, "utf8").digest("hex");
const eq = (a: unknown, b: unknown) => JSON.stringify(a) === JSON.stringify(b);

async function main(): Promise<void> {
  // --- constants ----------------------------------------------------------
  check(vectors.version === 1, "vectors version is 1");
  check(eq(vectors.constants.huePalette, [...HUE_PALETTE]), "HUE_PALETTE unchanged");
  check(
    eq(vectors.constants.hueFromIndexFirst8, Array.from({ length: 8 }, (_, i) => hueFromIndex(i))),
    "hueFromIndex unchanged"
  );

  // --- crypto: room derivation -------------------------------------------
  for (const r of vectors.crypto.rooms) {
    const { roomId } = await deriveRoomKeys(r.secret);
    check(roomId === r.roomId, `roomId for ${r.secret.slice(0, 8)}… (got ${roomId}, want ${r.roomId})`);
    check(isValidRoomId(roomId), `server accepts derived roomId ${roomId}`);
    // The first 16 raw bytes of the id are the HKDF "room-id" material.
    const raw = b64urlToBytes(roomId);
    const hex = [...raw.subarray(0, 16)].map((x) => x.toString(16).padStart(2, "0")).join("");
    check(hex === r.idMaterialHex, `room-id material for ${r.roomId}`);
  }

  // --- crypto: decrypt the committed ciphertexts ---------------------------
  // This is the direction that proves interop: a foreign implementation must be
  // able to read what this one wrote. (Re-encrypting would differ every run —
  // encryptJson uses a fresh random IV — so it is round-tripped instead.)
  for (const m of vectors.crypto.messages) {
    const { key, roomId } = await deriveRoomKeys(m.secret);
    check(roomId === m.roomId, `message roomId ${m.roomId}`);
    const got = await decryptJson<unknown>(key, m.ciphertext);
    check(eq(got, m.plaintext), `decrypt committed ciphertext for seed ${m.plaintext.seed}`);
    const rt = await decryptJson<unknown>(key, await encryptJson(key, m.plaintext));
    check(eq(rt, m.plaintext), `encrypt/decrypt round trip for seed ${m.plaintext.seed}`);
  }

  // --- crypto: the raw AES key in the vectors really is the derived key ----
  for (const r of vectors.crypto.rooms.slice(0, 2)) {
    const raw = Uint8Array.from((r.aesKeyHex as string).match(/../g)!.map((h) => parseInt(h, 16)));
    const imported = await crypto.subtle.importKey("raw", raw, "AES-GCM", false, ["encrypt"]);
    const iv = crypto.getRandomValues(new Uint8Array(12));
    const ct = new Uint8Array(
      await crypto.subtle.encrypt({ name: "AES-GCM", iv }, imported, new TextEncoder().encode('{"x":1}'))
    );
    const packed = new Uint8Array(12 + ct.length);
    packed.set(iv, 0);
    packed.set(ct, 12);
    const b64 = Buffer.from(packed).toString("base64url");
    const { key } = await deriveRoomKeys(r.secret);
    check(eq(await decryptJson(key, b64), { x: 1 }), `aesKeyHex matches derived key for ${r.roomId}`);
  }

  // --- crypto: invalid room ids -------------------------------------------
  for (const bad of vectors.crypto.invalidRoomIds) {
    check(!isValidRoomId(bad), `rejects invalid roomId ${bad}`);
  }

  // --- rng -----------------------------------------------------------------
  for (const r of vectors.rng) {
    check(cyrb53(r.seed) === r.cyrb53, `cyrb53("${r.seed}")`);
    check(cyrb53(r.seed, 0x9e37) === r.cyrb53Seed0x9e37, `cyrb53("${r.seed}", 0x9e37)`);
    check(cyrb53(r.seed, 0x1234) === r.cyrb53Seed0x1234, `cyrb53("${r.seed}", 0x1234)`);
    const gen = mulberry32(cyrb53(r.seed));
    const first5 = Array.from({ length: 5 }, () => gen());
    check(eq(first5, r.mulberry32First5), `mulberry32 stream for "${r.seed}"`);
  }

  // --- identity ------------------------------------------------------------
  for (const i of vectors.identity) {
    check(germanName(i.seed) === i.nameDe, `germanName("${i.seed}")`);
    check(englishName(i.seed) === i.nameEn, `englishName("${i.seed}")`);
    check(hueFromSeed(i.seed) === i.hueFromSeed, `hueFromSeed("${i.seed}")`);
    check(hslToCss(i.hueFromSeed, 72, 56) === i.colorFromSeed, `identity colour for "${i.seed}"`);
    check(sha256Hex(creatureSvg(i.seed)) === i.svgSha256Default, `bee SVG (seed hue) for "${i.seed}"`);
    check(sha256Hex(creatureSvg(i.seed, 210)) === i.svgSha256Hue210, `bee SVG (hue 210) for "${i.seed}"`);
  }
  for (const s of vectors.svgSamples) {
    check(creatureSvg(s.seed) === s.svg, `bee SVG sample matches verbatim for "${s.seed}"`);
  }

  for (const n of vectors.sharedNames) {
    check(sanitizeSharedName(n.input) === n.output, `sanitizeSharedName(${JSON.stringify(n.input)})`);
  }

  console.log(
    failures === 0
      ? `✓ vectors: ${checks} checks passed`
      : `✗ vectors: ${failures} of ${checks} checks FAILED — run \`npm run vectors\` only if the change is intentional`
  );
  process.exit(failures === 0 ? 0 : 1);
}

void main();
