/**
 * Wire protocol between browser and relay.
 *
 * IMPORTANT: everything the server can read lives here. The server routes by
 * `roomId` and fans out an OPAQUE, end-to-end-encrypted `data` blob. It never
 * sees coordinates, names, or the encryption key. The plaintext structure of
 * `data` (see client/src/crypto.ts) is deliberately NOT modelled here.
 */
import { z } from "zod";

/** A room id is base64url(24 bytes): 16 bytes of key material + 8 bytes checksum. */
export const ROOM_ID_LENGTH = 32;
export const roomIdSchema = z
  .string()
  .length(ROOM_ID_LENGTH)
  .regex(/^[A-Za-z0-9_-]+$/);

/** Client -> server. */
export const clientMessageSchema = z.discriminatedUnion("t", [
  // `cid` is an optional, ephemeral per-tab connection token (never an identity).
  // It lets the relay evict this tab's own stale socket when it reconnects (see
  // relay.joinRoom), so a standby/reload zombie can't double-count or replay.
  z.object({ t: z.literal("join"), roomId: roomIdSchema, cid: z.string().max(64).optional() }),
  // `data` is opaque ciphertext (base64url). Capped in size by the server.
  z.object({ t: z.literal("relay"), data: z.string().max(8192) }),
]);
export type ClientMessage = z.infer<typeof clientMessageSchema>;

/** Server -> client. */
export type ServerMessage =
  | { t: "hello"; selfId: string }
  | { t: "peer"; id: string; data: string }
  | { t: "request" } // a peer joined; please re-broadcast your latest state
  | { t: "left"; id: string }
  // Aggregate room occupancy so clients can show that watchers (present but not
  // sharing) exist — a plain count, never an identity or location.
  | { t: "presence"; n: number }
  | { t: "error"; reason: string };
