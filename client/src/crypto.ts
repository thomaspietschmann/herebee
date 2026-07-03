/**
 * End-to-end crypto. The whole security model lives here.
 *
 * A 256-bit secret is generated in the browser and kept in the URL fragment
 * (#...), which is NEVER sent to the server. From it we derive two independent
 * values via HKDF-SHA256:
 *   - roomId: 16 bytes of key material + an 8-byte SHA-256 checksum, base64url
 *     (32 chars). Only this leaves the browser, purely as a routing handle.
 *   - key:    an AES-256-GCM key that NEVER leaves the browser.
 * Every location/profile update is encrypted with a fresh 96-bit IV. The relay
 * only ever sees ciphertext + the opaque roomId.
 */

const FIXED_SALT = new TextEncoder().encode("localizer/v1");

export function bytesToB64url(bytes: Uint8Array): string {
  let bin = "";
  for (const b of bytes) bin += String.fromCharCode(b);
  return btoa(bin).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

export function b64urlToBytes(s: string): Uint8Array<ArrayBuffer> {
  const b64 = s.replace(/-/g, "+").replace(/_/g, "/");
  const pad = b64.length % 4 ? "=".repeat(4 - (b64.length % 4)) : "";
  const bin = atob(b64 + pad);
  const out = new Uint8Array(bin.length);
  for (let i = 0; i < bin.length; i++) out[i] = bin.charCodeAt(i);
  return out;
}

/** New 256-bit room secret, base64url. This IS the capability — share carefully. */
export function generateSecret(): string {
  return bytesToB64url(crypto.getRandomValues(new Uint8Array(32)));
}

async function hkdfKeyMaterial(secret: Uint8Array<ArrayBuffer>): Promise<CryptoKey> {
  return crypto.subtle.importKey("raw", secret, "HKDF", false, ["deriveBits", "deriveKey"]);
}

export interface RoomKeys {
  roomId: string;
  key: CryptoKey;
}

export async function deriveRoomKeys(secretB64: string): Promise<RoomKeys> {
  const secret = b64urlToBytes(secretB64);
  const hkdf = await hkdfKeyMaterial(secret);

  const idMaterial = new Uint8Array(
    await crypto.subtle.deriveBits(
      { name: "HKDF", hash: "SHA-256", salt: FIXED_SALT, info: new TextEncoder().encode("room-id") },
      hkdf,
      128
    )
  );
  const digest = new Uint8Array(await crypto.subtle.digest("SHA-256", idMaterial));
  const raw = new Uint8Array(24);
  raw.set(idMaterial, 0);
  raw.set(digest.subarray(0, 8), 16);
  const roomId = bytesToB64url(raw);

  const key = await crypto.subtle.deriveKey(
    { name: "HKDF", hash: "SHA-256", salt: FIXED_SALT, info: new TextEncoder().encode("aes-key") },
    hkdf,
    { name: "AES-GCM", length: 256 },
    false,
    ["encrypt", "decrypt"]
  );

  return { roomId, key };
}

export async function encryptJson(key: CryptoKey, value: unknown): Promise<string> {
  const iv = crypto.getRandomValues(new Uint8Array(12));
  const plaintext = new TextEncoder().encode(JSON.stringify(value));
  const ct = new Uint8Array(await crypto.subtle.encrypt({ name: "AES-GCM", iv }, key, plaintext));
  const packed = new Uint8Array(iv.length + ct.length);
  packed.set(iv, 0);
  packed.set(ct, iv.length);
  return bytesToB64url(packed);
}

export async function decryptJson<T>(key: CryptoKey, dataB64: string): Promise<T | null> {
  try {
    const packed = b64urlToBytes(dataB64);
    const iv = packed.subarray(0, 12);
    const ct = packed.subarray(12);
    const pt = await crypto.subtle.decrypt({ name: "AES-GCM", iv }, key, ct);
    return JSON.parse(new TextDecoder().decode(pt)) as T;
  } catch {
    return null; // wrong key, tampered, or garbage — ignore
  }
}
