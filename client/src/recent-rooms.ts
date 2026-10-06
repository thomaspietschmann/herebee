const ENABLED_KEY = "herebee.recentRooms.on";
const LIST_KEY = "herebee.recentRooms";
const MAX_ROOMS = 5;
const MAX_SEEDS = 4;
const TTL_MS = 3 * 24 * 60 * 60_000;
const SECRET = /^[A-Za-z0-9_-]{43}$/;

export interface RecentRoom {
  secret: string;
  roomId: string;
  at: number;
  seeds: string[];
}

function read(): RecentRoom[] {
  try {
    const raw = JSON.parse(localStorage.getItem(LIST_KEY) ?? "[]");
    if (!Array.isArray(raw)) return [];
    const now = Date.now();
    return raw
      .filter(
        (r): r is RecentRoom =>
          r &&
          typeof r.secret === "string" &&
          SECRET.test(r.secret) &&
          typeof r.roomId === "string" &&
          typeof r.at === "number" &&
          Array.isArray(r.seeds) &&
          now - r.at < TTL_MS
      )
      .slice(0, MAX_ROOMS);
  } catch {
    return [];
  }
}

function write(rooms: RecentRoom[]): void {
  try {
    if (rooms.length) localStorage.setItem(LIST_KEY, JSON.stringify(rooms));
    else localStorage.removeItem(LIST_KEY);
  } catch {
    return;
  }
}

export function recentEnabled(): boolean {
  try {
    return localStorage.getItem(ENABLED_KEY) === "1";
  } catch {
    return false;
  }
}

export function setRecentEnabled(on: boolean): void {
  try {
    if (on) localStorage.setItem(ENABLED_KEY, "1");
    else {
      localStorage.removeItem(ENABLED_KEY);
      localStorage.removeItem(LIST_KEY);
    }
  } catch {
    return;
  }
}

export function recentRooms(): RecentRoom[] {
  if (!recentEnabled()) return [];
  const rooms = read();
  write(rooms);
  return rooms;
}

export function rememberRoom(secret: string, roomId: string): void {
  if (!recentEnabled()) return;
  const rooms = read();
  const old = rooms.find((r) => r.secret === secret);
  const entry: RecentRoom = { secret, roomId, at: Date.now(), seeds: old?.seeds ?? [] };
  write([entry, ...rooms.filter((r) => r.secret !== secret)].slice(0, MAX_ROOMS));
}

export function rememberSeed(roomId: string, seed: string): void {
  if (!recentEnabled()) return;
  const rooms = read();
  const room = rooms.find((r) => r.roomId === roomId);
  if (!room || room.seeds.includes(seed) || room.seeds.length >= MAX_SEEDS) return;
  room.seeds.push(seed);
  write(rooms);
}

export function forgetRoom(secret: string): void {
  write(read().filter((r) => r.secret !== secret));
}

export function forgetAllRooms(keep?: string): void {
  write(read().filter((r) => r.secret === keep));
}

export function secretFromLink(text: string): string | null {
  const m = /#([A-Za-z0-9_-]{43})\s*$/.exec(text.trim());
  return m ? m[1] : null;
}
