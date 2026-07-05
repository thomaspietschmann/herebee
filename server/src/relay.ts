/**
 * In-memory room registry. Rooms are lazy: they come into existence when the
 * first socket joins and vanish the moment the last one leaves. Nothing is
 * persisted, so a server restart is invisible to clients — they reconnect and
 * re-create the same room from the id in their URL.
 *
 * The registry stores ONLY socket membership and an ephemeral per-socket id.
 * No coordinates, no names, no IPs.
 */
import type { WebSocket } from "ws";
import type { ServerMessage } from "../../shared/messages.js";

export interface Conn {
  readonly id: string; // ephemeral, per-connection, not linkable
  readonly ws: WebSocket;
  roomId: string | null;
  bucket: number; // rate-limit tokens
  lastRefill: number;
  alive: boolean; // heartbeat
  // Last encrypted blob this peer sent, kept in RAM only so a newcomer (or a
  // client returning from standby) sees everyone's last position immediately.
  // Still opaque ciphertext — the server never learns coordinates.
  lastData: string | null;
}

const rooms = new Map<string, Set<Conn>>();

export function send(conn: Conn, msg: ServerMessage): void {
  if (conn.ws.readyState !== conn.ws.OPEN) return;
  conn.ws.send(JSON.stringify(msg));
}

export function joinRoom(conn: Conn, roomId: string): void {
  conn.roomId = roomId;
  let room = rooms.get(roomId);
  if (!room) {
    room = new Set();
    rooms.set(roomId, room); // lazy creation
  }
  room.add(conn);
  send(conn, { t: "hello", selfId: conn.id });
  for (const other of room) {
    if (other === conn) continue;
    // Replay each peer's last position to the newcomer right away — even peers
    // whose device is asleep and can't answer a live request.
    if (other.lastData) send(conn, { t: "peer", id: other.id, data: other.lastData });
    // Also nudge awake peers to send a fresh one.
    send(other, { t: "request" });
  }
}

/** Fan out an opaque encrypted blob to every other member of the sender's room. */
export function relay(conn: Conn, data: string): void {
  if (!conn.roomId) return;
  const room = rooms.get(conn.roomId);
  if (!room) return;
  conn.lastData = data; // remember last ciphertext (RAM only) for newcomers
  const msg: ServerMessage = { t: "peer", id: conn.id, data };
  const payload = JSON.stringify(msg);
  for (const other of room) {
    if (other === conn) continue;
    if (other.ws.readyState !== other.ws.OPEN) continue;
    // Backpressure guard: drop for congested peers (latest-wins), never buffer.
    if (other.ws.bufferedAmount > 1_000_000) continue;
    other.ws.send(payload);
  }
}

export function leaveRoom(conn: Conn): void {
  const roomId = conn.roomId;
  if (!roomId) return;
  conn.roomId = null;
  const room = rooms.get(roomId);
  if (!room) return;
  room.delete(conn);
  if (room.size === 0) {
    rooms.delete(roomId); // self-healing: empty rooms disappear immediately
    return;
  }
  for (const other of room) send(other, { t: "left", id: conn.id });
}

export function stats(): { rooms: number; connections: number } {
  let connections = 0;
  for (const room of rooms.values()) connections += room.size;
  return { rooms: rooms.size, connections };
}
