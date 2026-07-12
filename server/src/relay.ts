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
  // Ephemeral per-tab token (from the client's sessionStorage), used ONLY to
  // recognise a reconnecting tab so we can drop its own stale socket. Never an
  // identity, never logged, gone when the tab closes.
  cid: string | null;
  bucket: number; // rate-limit tokens
  lastRefill: number;
  alive: boolean; // heartbeat
  // Last encrypted blob this peer sent, kept in RAM only so a newcomer (or a
  // client returning from standby) sees everyone's last position immediately.
  // Still opaque ciphertext — the server never learns coordinates.
  lastData: string | null;
}

const rooms = new Map<string, Set<Conn>>();

// Resource ceilings so a single client that mints unlimited valid roomIds (or
// fans many sockets into one room) can't exhaust memory. Generous for real use.
const MAX_ROOMS = Number(process.env.MAX_ROOMS ?? 5_000);
const MAX_CONNS_PER_ROOM = Number(process.env.MAX_CONNS_PER_ROOM ?? 100);

export function send(conn: Conn, msg: ServerMessage): void {
  if (conn.ws.readyState !== conn.ws.OPEN) return;
  conn.ws.send(JSON.stringify(msg));
}

/** Tell every member of a room the current occupancy (a bare count, no identity). */
function broadcastPresence(room: Set<Conn>): void {
  const msg: ServerMessage = { t: "presence", n: room.size };
  for (const c of room) send(c, msg);
}

export function joinRoom(conn: Conn, roomId: string, cid?: string): void {
  let room = rooms.get(roomId);
  // Capacity guards run before we commit the connection to the room.
  if (!room && rooms.size >= MAX_ROOMS) {
    send(conn, { t: "error", reason: "capacity" });
    try {
      conn.ws.close(1013, "capacity");
    } catch {
      /* already gone */
    }
    return;
  }
  if (room && room.size >= MAX_CONNS_PER_ROOM) {
    send(conn, { t: "error", reason: "room-full" });
    try {
      conn.ws.close(1013, "room-full");
    } catch {
      /* already gone */
    }
    return;
  }
  conn.roomId = roomId;
  conn.cid = cid ?? null;
  if (!room) {
    room = new Set();
    rooms.set(roomId, room); // lazy creation
  }
  // Evict a previous socket from the SAME browser tab (identified by cid): a
  // reload or standby-wake reconnect can leave the old socket lingering as a
  // "zombie" until the 20s heartbeat reaps it. Dropping it here keeps occupancy
  // honest and stops its stale cached blob from being replayed to newcomers.
  if (cid) {
    for (const other of room) {
      if (other === conn || other.cid !== cid) continue;
      room.delete(other);
      for (const c of room) send(c, { t: "left", id: other.id });
      try {
        other.ws.close();
      } catch {
        /* already gone */
      }
    }
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
  // Everyone (incl. the newcomer) learns the new occupancy, so watchers show up
  // as a count even though they never broadcast a position.
  broadcastPresence(room);
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
  broadcastPresence(room); // occupancy dropped by one
}

export function stats(): { rooms: number; connections: number } {
  let connections = 0;
  for (const room of rooms.values()) connections += room.size;
  return { rooms: rooms.size, connections };
}
