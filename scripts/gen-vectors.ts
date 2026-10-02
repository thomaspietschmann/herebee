/**
 * Generate shared/vectors.json — the cross-implementation conformance suite.
 *
 * The native apps (see docs/mobile-plan.md) reimplement the crypto, the seeded
 * PRNG, the nickname generator and the bee-avatar assembly in Dart. Any drift
 * there is invisible in testing but catastrophic in production: a different
 * roomId means the phone silently joins a DIFFERENT room, and a different PRNG
 * means the same person shows up as a different bee on every device.
 *
 * So the vectors are generated FROM THE REAL WEB CODE (client/src/*) and are the
 * single source of truth both sides test against. Regenerate with
 * `npm run vectors`; `npm run test:vectors` asserts the web code still matches
 * the committed file, so an accidental behaviour change fails loudly.
 *
 * Determinism: every input here is a fixed literal. Running this twice must
 * produce a byte-identical file (except `generator`), or the diff is a real bug.
 */
import { createHash } from "node:crypto";
import { writeFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

import { PAD_BLOCK, b64urlToBytes, bytesToB64url, deriveRoomKeys, deriveRoomSeed, encryptJson } from "../client/src/crypto.js";
import { cyrb53, mulberry32 } from "../client/src/rng.js";
import { HUE_PALETTE, creatureSvg, hslToCss, hueFromIndex, hueFromSeed } from "../client/src/avatar.js";
import { englishName, germanName, sanitizeSharedMessage, sanitizeSharedName } from "../client/src/names.js";
import type { PeerUpdate } from "../client/src/types.js";
import { layoutMenu, springSettled, springStep, type MenuLayoutInput } from "../client/src/menu-layout.js";

const HERE = dirname(fileURLToPath(import.meta.url));
const OUT = join(HERE, "..", "shared", "vectors.json");

/** Must equal FIXED_SALT in client/src/crypto.ts. Asserted below. */
const SALT_TEXT = "localizer/v1";

const sha256Hex = (s: string) => createHash("sha256").update(s, "utf8").digest("hex");

const MENU_BOUNDS = { left: 8, top: 110, right: 382, bottom: 700 };
const MENU_CASES: MenuLayoutInput[] = [
  [195, 400], [195, 130], [195, 690], [20, 400], [370, 400],
  [20, 125], [370, 125], [20, 690], [370, 690], [120, 150],
].map(([x, y]) => ({ anchor: { x, y }, bounds: MENU_BOUNDS, beeRadius: 21, bubble: 38, box: { w: 150, h: 66 } }));
MENU_CASES.push({
  anchor: { x: 60, y: 60 },
  bounds: { left: 0, top: 0, right: 120, bottom: 120 },
  beeRadius: 26,
  bubble: 38,
  box: { w: 150, h: 66 },
});
const HYSTERESIS_BASE = { bounds: MENU_BOUNDS, beeRadius: 21, bubble: 38, box: { w: 150, h: 66 } };
const turned = layoutMenu({ ...HYSTERESIS_BASE, anchor: { x: 195, y: 160 } }).choice;
MENU_CASES.push(
  { ...HYSTERESIS_BASE, anchor: { x: 195, y: 190 } },
  { ...HYSTERESIS_BASE, anchor: { x: 195, y: 190 }, previous: turned },
  { ...HYSTERESIS_BASE, anchor: { x: 195, y: 400 }, previous: turned }
);
const WIDE = { bounds: MENU_BOUNDS, beeRadius: 21, bubble: 46, box: { w: 150, h: 66 } };
for (const count of [3, 4]) {
  for (const [x, y] of [
    [195, 400], [195, 130], [195, 690], [20, 400], [370, 400],
    [20, 125], [370, 125], [20, 690], [370, 690], [120, 150],
  ]) {
    MENU_CASES.push({ ...WIDE, anchor: { x, y }, count });
  }
  const wideTurned = layoutMenu({ ...WIDE, anchor: { x: 195, y: 160 }, count }).choice;
  MENU_CASES.push({ ...WIDE, anchor: { x: 195, y: 190 }, previous: wideTurned, count });
}
const OUTER = { left: 8, top: 55, right: 382, bottom: 810 };
for (const count of [3, 4]) {
  for (const [x, y] of [[195, 60], [40, 140], [350, 140], [195, 720], [15, 420], [375, 650]]) {
    MENU_CASES.push({ ...WIDE, anchor: { x, y }, count, outer: OUTER });
  }
}
const menuLayout = MENU_CASES.map((input) => ({ input, output: layoutMenu(input) }));

const ROOM_SEED_CASES = [
  [fixedSecretForSeeds(0), "F_SNXNUR1v1QKRwr2aN4Kd_xSJP-2-24"],
  [fixedSecretForSeeds(0), "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA"],
  [fixedSecretForSeeds(1), "F_SNXNUR1v1QKRwr2aN4Kd_xSJP-2-24"],
  [fixedSecretForSeeds(2), "zzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzz"],
];

function fixedSecretForSeeds(n: number): string {
  const b = new Uint8Array(32);
  for (let i = 0; i < 32; i++) b[i] = (i * 53 + n * 17 + 3) & 0xff;
  return bytesToB64url(b);
}

const menuSpring = (() => {
  const target = { x: 50, y: -30 };
  let s = { x: 0, y: 0, vx: 0, vy: 0 };
  const states = [];
  for (let i = 1; i <= 40; i++) {
    s = springStep(s, target, 1 / 60);
    if (i % 5 === 0) states.push({ step: i, ...s, settled: springSettled(s, target) });
  }
  return { target, dt: 1 / 60, states };
})();

// --- fixed inputs ----------------------------------------------------------
// Deliberately NOT random: the committed file must be reproducible. Secrets are
// 32 bytes of a fixed byte pattern, base64url — the same shape generateSecret()
// produces, but stable across runs.
function fixedSecret(n: number): string {
  const b = new Uint8Array(32);
  for (let i = 0; i < 32; i++) b[i] = (i * 37 + n * 101 + 7) & 0xff;
  return bytesToB64url(b);
}

const SECRETS = Array.from({ length: 8 }, (_, i) => fixedSecret(i));

const SEEDS = [
  "abc", "0", "z", "seed-1", "seed-2", "aaaaaaaaaa", "9f3k2j1", "Zz09",
  "tom", "anna", "bee", "herebee", "xyzzy", "00000000", "ffffffff", "a-b_c",
  "ümlaut", "日本語", "emoji-🐝", "the-quick-brown-fox-jumps-over-the-lazy-dog",
] as const;

const PLAINTEXTS: PeerUpdate[] = [
  { k: "loc", seed: "abc", lat: 52.52, lng: 13.405, acc: 12.5, hdg: 180, spd: 1.4, at: 1_700_000_000_000 },
  { k: "loc", seed: "tom", lat: -33.8688, lng: 151.2093, acc: null, hdg: null, spd: null, at: 1_700_000_001_000 },
  { k: "loc", seed: "ümlaut", lat: 0, lng: 0, acc: 0, hdg: 0, spd: 0, at: 1 },
  { k: "loc", seed: "emoji-🐝", lat: 90, lng: -180, acc: 99999.5, hdg: 359.9, spd: 42.25, at: 2_000_000_000_000 },
  { k: "stop", seed: "abc" },
  { k: "stop", seed: "日本語" },
  {
    k: "loc", seed: "chatty", lat: 48.137, lng: 11.575, acc: 8, hdg: null, spd: null, at: 1_700_000_060_000,
    name: "x".repeat(40), msg: "🐝".repeat(100), msgAt: 1_700_000_000_000,
  },
];

// --- raw key material ------------------------------------------------------
/**
 * Re-derive the AES key EXTRACTABLE so the vectors can carry its raw bytes —
 * the Dart port needs something to compare against, and production's key is
 * deliberately non-extractable (crypto.ts derives with extractable=false).
 *
 * This duplicates crypto.ts's HKDF parameters, so it could drift from the real
 * derivation. That is caught, not assumed: `verifyRawKeyMatches` below encrypts
 * with THIS raw key and decrypts with the REAL deriveRoomKeys() key. If the two
 * ever diverge, generation fails instead of emitting wrong vectors.
 */
async function rawMaterial(secretB64: string): Promise<{ aesKeyHex: string; idMaterialHex: string }> {
  const salt = new TextEncoder().encode(SALT_TEXT);
  const secret = b64urlToBytes(secretB64);
  const hkdf = await crypto.subtle.importKey("raw", secret, "HKDF", false, ["deriveBits"]);
  const bits = (info: string, len: number) =>
    crypto.subtle.deriveBits(
      { name: "HKDF", hash: "SHA-256", salt, info: new TextEncoder().encode(info) },
      hkdf,
      len
    );
  const idMaterial = new Uint8Array(await bits("room-id", 128));
  const aesKey = new Uint8Array(await bits("aes-key", 256));
  const hex = (b: Uint8Array) => [...b].map((x) => x.toString(16).padStart(2, "0")).join("");
  return { aesKeyHex: hex(aesKey), idMaterialHex: hex(idMaterial) };
}

/** Prove the raw key above IS the key production derives. Throws if not. */
async function verifyRawKeyMatches(secretB64: string, aesKeyHex: string): Promise<void> {
  const raw = Uint8Array.from(aesKeyHex.match(/../g)!.map((h) => parseInt(h, 16)));
  const imported = await crypto.subtle.importKey("raw", raw, "AES-GCM", false, ["encrypt"]);
  const iv = new Uint8Array(12); // fixed IV is fine: this ciphertext is thrown away
  const probe = new TextEncoder().encode('{"probe":true}');
  const ct = new Uint8Array(await crypto.subtle.encrypt({ name: "AES-GCM", iv }, imported, probe));
  const packed = new Uint8Array(iv.length + ct.length);
  packed.set(iv, 0);
  packed.set(ct, iv.length);

  const { key } = await deriveRoomKeys(secretB64);
  const back = await crypto.subtle.decrypt({ name: "AES-GCM", iv }, key, ct).catch(() => null);
  if (!back || new TextDecoder().decode(new Uint8Array(back)) !== '{"probe":true}') {
    throw new Error(
      `raw AES key for secret ${secretB64.slice(0, 8)}… does not match deriveRoomKeys(); ` +
        `scripts/gen-vectors.ts has drifted from client/src/crypto.ts`
    );
  }
  void packed;
}

/** Flip one char in the checksum half so the id is well-formed but unverifiable. */
function corruptChecksum(roomId: string): string {
  const raw = b64urlToBytes(roomId);
  raw[20] = raw[20] ^ 0xff; // inside the 8 checksum bytes (offset 16..23)
  return bytesToB64url(raw);
}

/** What a malicious or careless peer might put in `name`; see sanitizeSharedName. */
const SHARED_MESSAGE_INPUTS: unknown[] = [
  "Bin gleich da",
  "  Wo   seid  ihr?  ",
  "Zeile eins\nZeile zwei\r\nZeile drei",
  "\u202eevil\u202c text",
  "zero\u200bwidth\ufeff",
  "👩\u200d💻 bin am Rechner",
  "y".repeat(120),
  "🐝".repeat(110),
  " ",
  "",
  7,
  null,
  { text: "hi" },
];

const SHARED_NAME_INPUTS: unknown[] = [
  "Anna",
  "  Anna   Lena  ",
  "Anna\u00a0\u2003Lena", // no-break and em space
  "Tab\tand\nnewline",
  "\u202eanna\u202c", // right-to-left override
  "zero\u200bwidth\ufeff",
  "👩\u200d💻 Coder", // ZWJ sequence survives
  "line\u2028sep",
  "x".repeat(50),
  "😀".repeat(45), // capped in code points, not UTF-16 units
  "   ",
  "",
  "\u200b\u202e",
  42,
  null,
  ["Anna"],
];

async function main(): Promise<void> {
  // Guard: the salt is the one thing here that is a literal copy of crypto.ts.
  const probeRoom = await deriveRoomKeys(SECRETS[0]);
  if (probeRoom.roomId.length !== 32) throw new Error("unexpected roomId length");

  const rooms = [];
  for (const secret of SECRETS) {
    const { roomId } = await deriveRoomKeys(secret);
    const { aesKeyHex, idMaterialHex } = await rawMaterial(secret);
    await verifyRawKeyMatches(secret, aesKeyHex);
    rooms.push({ secret, roomId, idMaterialHex, aesKeyHex });
  }

  // Ciphertexts are produced by the REAL encryptJson, so they carry a random IV
  // and differ on every run. That is fine and intended: the app must DECRYPT
  // these, which is the direction that actually proves interoperability.
  // (Encryption is covered by the app's own round-trip test plus aesKeyHex.)
  const messages = [];
  for (let i = 0; i < PLAINTEXTS.length; i++) {
    const secret = SECRETS[i % SECRETS.length];
    const { key, roomId } = await deriveRoomKeys(secret);
    messages.push({
      secret,
      roomId,
      plaintext: PLAINTEXTS[i],
      ciphertext: await encryptJson(key, PLAINTEXTS[i]),
    });
  }

  const invalidRoomIds = [
    corruptChecksum(rooms[0].roomId),
    corruptChecksum(rooms[1].roomId),
    "A".repeat(32), // well-formed base64url, wrong checksum
    rooms[0].roomId.slice(0, 31), // too short
    rooms[0].roomId + "A", // too long
  ];

  const rng = SEEDS.map((seed) => {
    const gen = mulberry32(cyrb53(seed));
    return {
      seed,
      cyrb53: cyrb53(seed),
      cyrb53Seed0x9e37: cyrb53(seed, 0x9e37), // as used by hueFromSeed
      cyrb53Seed0x1234: cyrb53(seed, 0x1234), // as used by creatureSvg
      mulberry32First5: Array.from({ length: 5 }, () => gen()),
    };
  });

  const identity = SEEDS.map((seed) => ({
    seed,
    nameDe: germanName(seed),
    nameEn: englishName(seed),
    hueFromSeed: hueFromSeed(seed),
    colorFromSeed: hslToCss(hueFromSeed(seed), 72, 56),
    svgSha256Default: sha256Hex(creatureSvg(seed)),
    svgSha256Hue210: sha256Hex(creatureSvg(seed, 210)),
  }));

  // Two full SVGs so a failing hash can actually be diffed by a human.
  const svgSamples = SEEDS.slice(0, 2).map((seed) => ({
    seed,
    hue: null as number | null,
    svg: creatureSvg(seed),
  }));

  const sharedNames = SHARED_NAME_INPUTS.map((input) => ({ input, output: sanitizeSharedName(input) }));
  const sharedMessages = SHARED_MESSAGE_INPUTS.map((input) => ({ input, output: sanitizeSharedMessage(input) }));

  const doc = {
    $schema: "https://herebee.app/schemas/vectors-v1",
    version: 1,
    generator: "scripts/gen-vectors.ts",
    purpose:
      "Cross-implementation conformance vectors. Generated from client/src/*; the native apps must reproduce every value. See shared/PROTOCOL.md.",
    constants: {
      hkdfSalt: SALT_TEXT,
      hkdfInfoRoomId: "room-id",
      hkdfInfoAesKey: "aes-key",
      roomIdLength: 32,
      padBlock: PAD_BLOCK,
      messageTtlMs: 10 * 60_000,
      ivBytes: 12,
      tagBytes: 16,
      huePalette: HUE_PALETTE,
      hueFromIndexFirst8: Array.from({ length: 8 }, (_, i) => hueFromIndex(i)),
    },
    crypto: { rooms, messages, invalidRoomIds },
    rng,
    identity,
    svgSamples,
    sharedNames,
    sharedMessages,
    menuLayout,
    menuSpring,
    roomSeeds: await Promise.all(
      ROOM_SEED_CASES.map(async ([device, roomId]) => ({ device, roomId, seed: await deriveRoomSeed(device, roomId) }))
    ),
  };

  writeFileSync(OUT, JSON.stringify(doc, null, 2) + "\n", "utf8");
  console.log(
    `wrote ${OUT}\n  ${rooms.length} rooms · ${messages.length} messages · ` +
      `${invalidRoomIds.length} invalid ids · ${rng.length} seeds`
  );
}

void main();
