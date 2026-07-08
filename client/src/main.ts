/**
 * App orchestrator: wires crypto -> net -> map/markers -> UI.
 *
 * Room identity comes entirely from the URL fragment secret. If none is present
 * we mint one and put it in the hash, so opening "/" lands you in a fresh room
 * whose link you can share. The path is cosmetic; the hash is the capability.
 */
import { deriveRoomKeys, generateSecret, type RoomKeys } from "./crypto.js";
import { NetClient } from "./net.js";
import { createCoordinator } from "./coord.js";
import { initMap } from "./map.js";
import { MarkerManager } from "./markers.js";
import { identityFromSeed } from "./avatar.js";
import { nameFromSeed } from "./names.js";
import { UI } from "./ui.js";
import { t, applyStaticI18n } from "./i18n.js";
import type { PeerUpdate, Position } from "./types.js";

function ensureSecret(): string {
  let secret = location.hash.replace(/^#/, "");
  if (!secret) {
    secret = generateSecret();
    history.replaceState(null, "", `/r/#${secret}`);
  } else if (location.pathname !== "/r/") {
    history.replaceState(null, "", `/r/#${secret}`);
  }
  return secret;
}

const mintToken = () => crypto.getRandomValues(new Uint8Array(9)).reduce((s, b) => s + b.toString(36), "");

function ownSeed(): string {
  const KEY = "herebee.seed";
  // localStorage (not sessionStorage): identity must be stable across reloads AND
  // shared between tabs of the same browser. Otherwise every new tab is a different
  // person (spawning phantom duplicates via the server's last-blob replay) and the
  // per-seed custom names persisted in localStorage would never survive a session.
  try {
    let seed = localStorage.getItem(KEY);
    if (!seed) {
      seed = mintToken();
      localStorage.setItem(KEY, seed);
    }
    return seed;
  } catch {
    // Private mode: localStorage throws. Keep at least a per-tab-stable identity in
    // sessionStorage so a reload doesn't silently turn us into a brand-new person.
    try {
      let seed = sessionStorage.getItem(KEY);
      if (!seed) {
        seed = mintToken();
        sessionStorage.setItem(KEY, seed);
      }
      return seed;
    } catch {
      return mintToken(); // truly no storage: ephemeral per-load identity
    }
  }
}

/**
 * Ephemeral per-TAB connection token. sessionStorage is scoped to one tab and
 * survives that tab's reloads, so a reconnecting tab reuses its cid and the relay
 * can drop its own stale socket (see relay.joinRoom). A second tab gets a fresh
 * cid — it's a genuinely separate socket. Never an identity; never leaves as one.
 */
function ownCid(): string {
  const KEY = "herebee.cid";
  try {
    let cid = sessionStorage.getItem(KEY);
    if (!cid) {
      cid = mintToken();
      sessionStorage.setItem(KEY, cid);
    }
    return cid;
  } catch {
    return mintToken();
  }
}

/**
 * Cross-tab bus protocol (BroadcastChannel, one browser only — never the network).
 * The leader tab owns the socket + GPS and mirrors state to follower tabs; the
 * followers render it and send their button intents back.
 */
type PeerSnap = { seed: string; lat: number; lng: number; acc: number | null; hdg: number | null; at: number };
type Bus =
  | { t: "hello" } // a tab just opened: leader, please send a snapshot
  | { t: "enter" } // a tab entered the room: the browser is now present
  | { t: "snapshot"; peers: PeerSnap[]; self: Position | null; sharing: boolean; presence: number; connected: boolean }
  | { t: "peer"; u: PeerUpdate } // leader -> followers: a peer update (never self)
  | { t: "self"; pos: Position | null } // leader -> followers: our own position
  | { t: "sharing"; on: boolean } // leader -> followers: sharing on/off
  | { t: "presence"; n: number }
  | { t: "status"; connected: boolean }
  | { t: "fatal"; reason: string }
  | { t: "rename"; seed: string } // any tab: a local custom name changed
  | { t: "toggle-share" }; // follower -> leader: please flip sharing

async function main(): Promise<void> {
  // Localize the static HUD (title, <html lang>, button labels, aria) up front.
  applyStaticI18n();

  // The map always renders first, so an unusable link never leaves a blank page.
  const map = initMap(document.getElementById("map")!);

  // Local, client-only custom names (never sent anywhere).
  const nameKey = (seed: string) => "herebee.name." + seed;
  const customName = (seed: string): string | null => {
    try {
      return localStorage.getItem(nameKey(seed));
    } catch {
      return null;
    }
  };
  const resolveName = (seed: string) => customName(seed) || nameFromSeed(seed);

  const seed = ownSeed();
  const cid = ownCid();
  const roster = new Map<string, { color: string; name: string }>();
  const rosterName = (s: string) => (s === seed ? `${resolveName(s)} ${t("youSuffix")}` : resolveName(s));
  // presence = total participants in the room (a count from the server). Because
  // one browser now holds exactly one socket, this counts people, not tabs.
  // watchers = present but not sharing a location; shown anonymously.
  let presence = 0;
  const refreshRoster = () => {
    const sharers = [...roster.entries()]
      .map(([s, v]) => ({ seed: s, color: v.color, name: v.name }))
      .sort((a, b) => a.name.localeCompare(b.name));
    const watchers = Math.max(0, presence - sharers.length);
    ui.setRoster(sharers, watchers, presence);
  };

  const markers = new MarkerManager(map, (s) => onRename(s));
  const fitAll = () => {
    const b = markers.bounds();
    if (b) map.fitBounds(b, { padding: 80, maxZoom: 16, duration: 700 });
  };
  const goTo = (s: string) => {
    const p = markers.positionOf(s);
    if (p) map.easeTo({ center: p, zoom: Math.max(map.getZoom(), 15), duration: 700 });
  };
  const ui = new UI({
    // The leader owns sharing; a follower just asks it to flip via the bus.
    onToggleShare: () => (coord.isLeader() ? toggleShare() : coord.post({ t: "toggle-share" } satisfies Bus)),
    onFitAll: fitAll,
    onGoTo: goTo,
  });

  // Derive the room keys from the fragment secret. A hand-edited / malformed
  // secret can't decode — show a friendly notice instead of failing silently.
  let keys: RoomKeys;
  try {
    keys = await deriveRoomKeys(ensureSecret());
  } catch {
    ui.openInvalidLink();
    return;
  }

  // Remember (per room) whether we were sharing, and restore it after a reload.
  const shareKey = "herebee.sharing." + keys.roomId;
  const rememberSharing = (on: boolean) => {
    try {
      if (on) localStorage.setItem(shareKey, "1");
      else localStorage.removeItem(shareKey);
    } catch {
      /* private mode */
    }
  };

  // ---- rendering (runs in EVERY tab) -------------------------------------
  // These paint the map/roster from whatever source: the leader feeds them from
  // the live socket + GPS; followers feed them from the bus. Keeping them source-
  // agnostic is what lets a promoted follower keep rendering seamlessly.
  let centeredOnSelf = false;

  function renderPeer(update: PeerUpdate): void {
    if (update.k === "stop") {
      markers.remove(update.seed); // active stop -> disappear now
      roster.delete(update.seed);
      refreshRoster();
      return;
    }
    const peer = identityFromSeed(update.seed, resolveName(update.seed));
    markers.upsert(update.seed, peer, { lat: update.lat, lng: update.lng, acc: update.acc, hdg: update.hdg }, update.at);
    roster.set(update.seed, { color: peer.color, name: rosterName(update.seed) });
    refreshRoster();
  }

  function renderSelf(pos: Position | null): void {
    if (!pos) {
      markers.remove(seed);
      roster.delete(seed);
      refreshRoster();
      return;
    }
    const self = identityFromSeed(seed, resolveName(seed));
    markers.upsert(seed, self, pos, Date.now(), true);
    roster.set(seed, { color: self.color, name: rosterName(seed) });
    refreshRoster();
    if (!centeredOnSelf) {
      map.easeTo({ center: [pos.lng, pos.lat], zoom: 15, duration: 900 });
      centeredOnSelf = true;
    }
  }

  function onRename(s: string): void {
    ui.openRename(resolveName(s), !!customName(s), (name) => {
      try {
        if (name) localStorage.setItem(nameKey(s), name);
        else localStorage.removeItem(nameKey(s));
      } catch {
        /* private mode: names just won't persist */
      }
      markers.rename(s, resolveName(s));
      const entry = roster.get(s);
      if (entry) {
        entry.name = rosterName(s);
        refreshRoster();
      }
      coord.post({ t: "rename", seed: s } satisfies Bus); // reflect it in sibling tabs
    });
  }

  // ---- engine (runs in the LEADER tab only) ------------------------------
  let net: NetClient | null = null;
  let watchId: number | null = null;
  let heartbeatId: number | null = null;
  let lastPos: Position | null = null;
  let connected = false;
  let browserEntered = false; // has ANY tab of this browser entered the room?
  let engineLive = false; // has the leader's socket been opened?

  function locUpdate(pos: Position): PeerUpdate {
    return { k: "loc", seed, lat: pos.lat, lng: pos.lng, acc: pos.acc, hdg: pos.hdg, at: Date.now() };
  }

  function leaderStartShare(): void {
    if (watchId !== null) return; // already sharing (idempotent)
    if (!("geolocation" in navigator)) {
      ui.toast(t("noGeo"));
      return;
    }
    watchId = navigator.geolocation.watchPosition(
      (p) => {
        const pos: Position = {
          lat: p.coords.latitude,
          lng: p.coords.longitude,
          acc: Number.isFinite(p.coords.accuracy) ? p.coords.accuracy : null,
          hdg: Number.isFinite(p.coords.heading as number) ? (p.coords.heading as number) : null,
        };
        lastPos = pos;
        renderSelf(pos);
        coord.post({ t: "self", pos } satisfies Bus);
        void net?.broadcast(locUpdate(pos));
      },
      (err) => {
        leaderStopShare();
        ui.toast(t(err.code === err.PERMISSION_DENIED ? "geoDenied" : "geoUnavailable"));
      },
      { enableHighAccuracy: true, maximumAge: 3000, timeout: 12000 }
    );
    // Desktop geolocation is static, so watchPosition may fire only once. Re-send
    // the last position on a heartbeat so our marker stays fresh for peers (and
    // the server's cached blob stays current for newcomers) even while stationary.
    heartbeatId = window.setInterval(() => {
      if (!lastPos) return;
      renderSelf(lastPos);
      coord.post({ t: "self", pos: lastPos } satisfies Bus);
      void net?.broadcast(locUpdate(lastPos));
    }, 10_000);
    ui.setSharing(true);
    coord.post({ t: "sharing", on: true } satisfies Bus);
    rememberSharing(true);
  }

  function leaderStopShare(): void {
    if (watchId !== null) {
      navigator.geolocation.clearWatch(watchId);
      watchId = null;
    }
    if (heartbeatId !== null) {
      clearInterval(heartbeatId);
      heartbeatId = null;
    }
    if (lastPos) void net?.broadcast({ k: "stop", seed });
    lastPos = null;
    renderSelf(null);
    coord.post({ t: "self", pos: null } satisfies Bus);
    ui.setSharing(false);
    coord.post({ t: "sharing", on: false } satisfies Bus);
    rememberSharing(false);
  }

  function toggleShare(): void {
    if (watchId === null) leaderStartShare();
    else leaderStopShare();
  }

  /** Hand a freshly-opened follower the full current state in one shot. */
  function sendSnapshot(): void {
    if (!browserEntered) return; // nothing to show until the browser has entered
    const peers = markers
      .dump()
      .filter((e) => !e.self)
      .map((e) => ({ seed: e.id, lat: e.pos.lat, lng: e.pos.lng, acc: e.pos.acc, hdg: e.pos.hdg, at: e.at }));
    coord.post({ t: "snapshot", peers, self: lastPos, sharing: watchId !== null, presence, connected } satisfies Bus);
  }

  /** Open the leader's socket (once) if the browser has entered. Idempotent. */
  function ensureConnected(): void {
    if (engineLive || !coord.isLeader() || !net || !browserEntered) return;
    engineLive = true;
    net.connect();
    try {
      if (localStorage.getItem(shareKey) === "1") leaderStartShare();
    } catch {
      /* private mode */
    }
  }

  // Built the instant this tab wins leadership (immediately for a lone tab, or
  // later if promoted after the previous leader closed). If the browser had
  // already entered, connect right away so presence is seamless across handoff.
  function buildEngine(): void {
    net = new NetClient(keys, cid, {
      // Markers are keyed by identity seed (stable across reconnects), so a dropped
      // and restored connection updates the same marker instead of duplicating it.
      onPeer(_id, update: PeerUpdate) {
        // Ignore replays of our own identity. The server replays each peer's last
        // cached blob on join, so a lingering old socket would otherwise feed us
        // our own stale "stop"/ghost. Our own marker is owned by sharing.
        if (update.seed === seed) return;
        renderPeer(update);
        coord.post({ t: "peer", u: update } satisfies Bus);
      },
      // Connection lost: keep the ghost — it lingers up to 20 min then self-removes.
      onLeft() {},
      onRequest() {
        if (lastPos) void net?.broadcast(locUpdate(lastPos));
      },
      onStatus(c) {
        connected = c;
        ui.setConnection(c ? "on" : "off");
        coord.post({ t: "status", connected: c } satisfies Bus);
      },
      onPresence(n) {
        presence = n;
        refreshRoster();
        coord.post({ t: "presence", n } satisfies Bus);
      },
      onFatal(reason) {
        ui.setConnection("off");
        ui.toast(t(reason === "invalid-room" ? "fatalInvalidRoom" : "fatalRejected"));
        coord.post({ t: "fatal", reason } satisfies Bus);
      },
    });
    ensureConnected();
  }

  // ---- cross-tab coordination -------------------------------------------
  // Exactly one tab per browser+room becomes leader (owns socket + GPS); the rest
  // follow. Scoped per roomId, so a different room in another tab is independent.
  const coord = createCoordinator(keys.roomId, buildEngine);

  coord.onMessage((m: Bus) => {
    switch (m.t) {
      case "hello":
        if (coord.isLeader()) sendSnapshot(); // self-guards on browserEntered
        break;
      case "enter":
        // Another tab entered -> the browser is present. Dismiss our own gate and,
        // if we're the (idle) leader, open the connection now.
        browserEntered = true;
        ui.dismissWelcome();
        ensureConnected();
        break;
      case "snapshot":
        if (coord.isLeader()) break; // only followers consume snapshots
        browserEntered = true;
        ui.dismissWelcome();
        for (const p of m.peers) {
          renderPeer({ k: "loc", seed: p.seed, lat: p.lat, lng: p.lng, acc: p.acc, hdg: p.hdg, at: p.at });
        }
        renderSelf(m.self);
        ui.setSharing(m.sharing);
        presence = m.presence;
        connected = m.connected;
        ui.setConnection(m.connected ? "on" : "off");
        refreshRoster();
        break;
      case "peer":
        if (!coord.isLeader()) renderPeer(m.u);
        break;
      case "self":
        if (!coord.isLeader()) renderSelf(m.pos);
        break;
      case "sharing":
        if (!coord.isLeader()) ui.setSharing(m.on);
        break;
      case "presence":
        if (!coord.isLeader()) {
          presence = m.n;
          refreshRoster();
        }
        break;
      case "status":
        if (!coord.isLeader()) {
          connected = m.connected;
          ui.setConnection(m.connected ? "on" : "off");
        }
        break;
      case "fatal":
        if (!coord.isLeader()) {
          ui.setConnection("off");
          ui.toast(t(m.reason === "invalid-room" ? "fatalInvalidRoom" : "fatalRejected"));
        }
        break;
      case "rename": {
        // A custom name changed in some tab. Re-resolve it everywhere.
        markers.rename(m.seed, resolveName(m.seed));
        const e = roster.get(m.seed);
        if (e) {
          e.name = rosterName(m.seed);
          refreshRoster();
        }
        break;
      }
      case "toggle-share":
        if (coord.isLeader()) toggleShare();
        break;
    }
  });

  // Entry gate: nothing touches the network (or geolocation) until the user
  // actively enters via the splash — becoming present is a deliberate act. Once
  // ANY tab of this browser has entered, sibling tabs auto-dismiss (consent was
  // given for the browser), so you don't confirm the gate once per tab.
  const doEnter = () => {
    if (browserEntered) return;
    browserEntered = true;
    coord.post({ t: "enter" } satisfies Bus); // tell siblings the browser is present
    ensureConnected(); // connects only if we're the leader; else the leader will
  };
  ui.openWelcome(doEnter);
  // Ask an already-present leader for a snapshot; if one answers, our gate is
  // auto-dismissed. A lone / first tab gets no reply and keeps its gate.
  coord.post({ t: "hello" } satisfies Bus);

  // Returning from standby / a tab switch can leave the socket frozen and pauses
  // geolocation. Only the leader owns the socket, so only it resyncs; followers
  // simply keep rendering what the leader relays.
  const resume = () => {
    if (coord.isLeader() && engineLive && document.visibilityState === "visible") net?.resync();
  };
  document.addEventListener("visibilitychange", resume);
  window.addEventListener("online", resume);
  window.addEventListener("pageshow", resume);

  // Age markers once a second; keep the roster in sync when peers time out. Runs
  // in every tab, since every tab renders its own markers.
  setInterval(() => {
    for (const id of markers.tick()) {
      roster.delete(id);
    }
    refreshRoster();
  }, 1000);

  // Deliberately no "stop" on pagehide: simply closing the tab or losing signal
  // should let peers keep the ghost for a while, not remove it instantly. Only
  // the explicit "Teilen stoppen" button broadcasts a stop.
}

void main();
