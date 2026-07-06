/**
 * App orchestrator: wires crypto -> net -> map/markers -> UI.
 *
 * Room identity comes entirely from the URL fragment secret. If none is present
 * we mint one and put it in the hash, so opening "/" lands you in a fresh room
 * whose link you can share. The path is cosmetic; the hash is the capability.
 */
import { deriveRoomKeys, generateSecret, type RoomKeys } from "./crypto.js";
import { NetClient } from "./net.js";
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

function ownSeed(): string {
  const KEY = "herebee.seed";
  const mint = () => crypto.getRandomValues(new Uint8Array(9)).reduce((s, b) => s + b.toString(36), "");
  // localStorage (not sessionStorage): identity must be stable across reloads AND
  // shared between tabs of the same browser. Otherwise every new tab is a different
  // person (spawning phantom duplicates via the server's last-blob replay) and the
  // per-seed custom names persisted in localStorage would never survive a session.
  try {
    let seed = localStorage.getItem(KEY);
    if (!seed) {
      seed = mint();
      localStorage.setItem(KEY, seed);
    }
    return seed;
  } catch {
    return mint(); // private mode: fall back to an ephemeral identity
  }
}

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
  const roster = new Map<string, { color: string; name: string }>();
  const rosterName = (s: string) => (s === seed ? `${resolveName(s)} ${t("youSuffix")}` : resolveName(s));
  // presence = total connections in the room (from the server, a count only).
  // watchers = present but not sharing a location; shown anonymously.
  let presence = 0;
  const refreshRoster = () => {
    const sharers = [...roster.entries()]
      .map(([s, v]) => ({ seed: s, color: v.color, name: v.name }))
      .sort((a, b) => a.name.localeCompare(b.name));
    const watchers = Math.max(0, presence - sharers.length);
    ui.setRoster(sharers, watchers, presence);
  };

  let watchId: number | null = null;
  let heartbeatId: number | null = null;
  let lastPos: Position | null = null;
  let centeredOnSelf = false;
  let entered = false; // true once the user confirmed the entry gate (WS live)

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
    onToggleShare: () => (watchId === null ? startSharing() : stopSharing()),
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
    });
  }

  const net = new NetClient(keys, {
    // Markers are keyed by identity seed (stable across reconnects), so a dropped
    // and restored connection updates the same marker instead of duplicating it.
    onPeer(_id, update: PeerUpdate) {
      // Ignore anything about our own identity. The server replays each peer's last
      // cached blob on join, so a lingering old socket (reload / second tab) would
      // otherwise feed us our own stale "stop" (wiping our fresh self marker) or a
      // duplicate non-self ghost of ourselves. Our own marker is owned by sharing.
      if (update.seed === seed) return;
      if (update.k === "stop") {
        markers.remove(update.seed); // active stop -> disappear now
        roster.delete(update.seed);
        refreshRoster();
        return;
      }
      const peer = identityFromSeed(update.seed, resolveName(update.seed));
      markers.upsert(
        update.seed,
        peer,
        { lat: update.lat, lng: update.lng, acc: update.acc, hdg: update.hdg },
        update.at
      );
      roster.set(update.seed, { color: peer.color, name: rosterName(update.seed) });
      refreshRoster();
    },
    // Connection lost: keep the ghost — it lingers up to 20 min then self-removes.
    onLeft() {},
    onRequest() {
      if (lastPos) void net.broadcast(locUpdate(lastPos));
    },
    onStatus(connected) {
      ui.setConnection(connected ? "on" : "off");
    },
    onPresence(n) {
      presence = n;
      refreshRoster();
    },
    onFatal(reason) {
      ui.setConnection("off");
      ui.toast(t(reason === "invalid-room" ? "fatalInvalidRoom" : "fatalRejected"));
    },
  });

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

  // Entry gate: nothing touches the network (or geolocation) until the user
  // actively enters via the splash. Opening the socket is what makes us "present"
  // to others, so it must be a deliberate act — see the splash copy.
  // Always gate behind the splash — every load, every room. Nothing touches the
  // network (or geolocation) until the user actively confirms entering the room.
  const enterRoom = () => {
    if (entered) return;
    entered = true;
    net.connect();
    // Resume sharing from a previous visit to this room (only now, post-entry).
    try {
      if (localStorage.getItem(shareKey) === "1") startSharing();
    } catch {
      /* private mode */
    }
  };
  ui.openWelcome(enterRoom);

  // Returning from standby / a tab switch can leave the socket frozen and pauses
  // geolocation. Re-establish the connection so peers re-sync both directions —
  // but only once we've actually entered (never before the gate is confirmed).
  const resume = () => {
    if (entered && document.visibilityState === "visible") net.resync();
  };
  document.addEventListener("visibilitychange", resume);
  window.addEventListener("online", resume);
  window.addEventListener("pageshow", resume);

  function locUpdate(pos: Position): PeerUpdate {
    return { k: "loc", seed, lat: pos.lat, lng: pos.lng, acc: pos.acc, hdg: pos.hdg, at: Date.now() };
  }

  function startSharing(): void {
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
        const self = identityFromSeed(seed, resolveName(seed));
        markers.upsert(seed, self, pos, Date.now(), true);
        roster.set(seed, { color: self.color, name: rosterName(seed) });
        refreshRoster();
        if (!centeredOnSelf) {
          map.easeTo({ center: [pos.lng, pos.lat], zoom: 15, duration: 900 });
          centeredOnSelf = true;
        }
        void net.broadcast(locUpdate(pos));
      },
      (err) => {
        stopSharing();
        ui.toast(t(err.code === err.PERMISSION_DENIED ? "geoDenied" : "geoUnavailable"));
      },
      { enableHighAccuracy: true, maximumAge: 3000, timeout: 12000 }
    );
    // Desktop geolocation is static, so watchPosition may fire only once. Re-send
    // the last position on a heartbeat so our marker stays fresh for peers (and
    // the server's cached blob stays current for newcomers) even while stationary.
    heartbeatId = window.setInterval(() => {
      if (!lastPos) return;
      const self = identityFromSeed(seed, resolveName(seed));
      markers.upsert(seed, self, lastPos, Date.now(), true);
      void net.broadcast(locUpdate(lastPos));
    }, 10_000);
    ui.setSharing(true);
    rememberSharing(true);
  }

  function stopSharing(): void {
    if (watchId !== null) {
      navigator.geolocation.clearWatch(watchId);
      watchId = null;
    }
    if (heartbeatId !== null) {
      clearInterval(heartbeatId);
      heartbeatId = null;
    }
    if (lastPos) void net.broadcast({ k: "stop", seed });
    lastPos = null;
    markers.remove(seed);
    roster.delete(seed);
    refreshRoster();
    ui.setSharing(false);
    rememberSharing(false);
  }

  // Age markers once a second; keep the roster in sync when peers time out.
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
