/**
 * Self-certifying room ids.
 *
 * A room id is base64url(24 bytes) = 32 chars, where the last 8 bytes are the
 * SHA-256 prefix of the first 16. The client derives the 16 key bytes from the
 * URL-fragment secret via HKDF and appends the checksum. The server only ever
 * VERIFIES the checksum — it holds no state, so this survives restarts.
 *
 * Effect: nobody can hand-pick or guess a valid id (forgery chance 2^-64), and
 * short vanity codes are impossible because the length is fixed. Any well-formed
 * id lazily (re-)creates its room on join.
 */
import { createHash } from "node:crypto";
import { ROOM_ID_LENGTH } from "../../shared/messages.js";

function fromBase64url(s: string): Buffer | null {
  if (!/^[A-Za-z0-9_-]+$/.test(s)) return null;
  try {
    return Buffer.from(s, "base64url");
  } catch {
    return null;
  }
}

export function isValidRoomId(roomId: unknown): roomId is string {
  if (typeof roomId !== "string" || roomId.length !== ROOM_ID_LENGTH) return false;
  const raw = fromBase64url(roomId);
  if (!raw || raw.length !== 24) return false;
  const material = raw.subarray(0, 16);
  const checksum = raw.subarray(16, 24);
  const expected = createHash("sha256").update(material).digest().subarray(0, 8);
  return checksum.equals(expected);
}
