/**
 * App orchestrator: wires crypto -> net -> map/markers -> UI.
 *
 * Room identity comes entirely from the URL fragment secret. If none is present
 * we mint one and put it in the hash, so opening "/" lands you in a fresh room
 * whose link you can share. The path is cosmetic; the hash is the capability.
 */
import { deriveRoomKeys, generateSecret } from "./crypto.js";
import { NetClient } from "./net.js";
import { initMap } from "./map.js";
import { MarkerManager } from "./markers.js";
import { identityFromSeed, type Identity } from "./avatar.js";
import { nameFromSeed } from "./names.js";
import { UI } from "./ui.js";
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
  const KEY = "localizer.seed";
  let seed = sessionStorage.getItem(KEY);
  if (!seed) {
    seed = crypto.getRandomValues(new Uint8Array(9)).reduce((s, b) => s + b.toString(36), "");
    sessionStorage.setItem(KEY, seed);
  }
  return seed;
}

async function main(): Promise<void> {
  const keys = await deriveRoomKeys(ensureSecret());
  const map = initMap(document.getElementById("map")!);
  const markers = new MarkerManager(map);

  const seed = ownSeed();
  const self: Identity = identityFromSeed(seed, nameFromSeed(seed));

  // Roster: id -> minimal identity (self under the "self" id).
  const roster = new Map<string, { color: string; name: string }>();
  const refreshRoster = () =>
    ui.setRoster([...roster.values()].sort((a, b) => a.name.localeCompare(b.name)));

  let watchId: number | null = null;
  let lastPos: Position | null = null;
  let centeredOnSelf = false;

  const ui = new UI({ onToggleShare: () => (watchId === null ? startSharing() : stopSharing()) });

  // Explain watching vs. sharing once per session when entering the room.
  if (!sessionStorage.getItem("herebee.welcomed")) {
    ui.openWelcome();
    sessionStorage.setItem("herebee.welcomed", "1");
  }

  const net = new NetClient(keys, {
    // Markers are keyed by the peer's identity seed (stable across reconnects),
    // NOT the ephemeral socket id — so a dropped-and-restored connection updates
    // the same marker instead of spawning a duplicate.
    onPeer(_id, update: PeerUpdate) {
      if (update.k === "stop") {
        markers.remove(update.seed); // active stop -> disappear now
        roster.delete(update.seed);
        refreshRoster();
        return;
      }
      const peer = identityFromSeed(update.seed, nameFromSeed(update.seed));
      markers.upsert(
        update.seed,
        peer,
        { lat: update.lat, lng: update.lng, acc: update.acc, hdg: update.hdg },
        update.at
      );
      roster.set(update.seed, { color: peer.color, name: peer.name });
      refreshRoster();
    },
    // Connection lost (tab closed / dropped): keep the ghost — MarkerManager
    // lets it linger up to 20 min and then removes it on its own.
    onLeft() {},
    onRequest() {
      if (lastPos) void net.broadcast(locUpdate(lastPos));
    },
    onStatus(connected) {
      ui.setConnection(connected ? "on" : "off");
    },
    onFatal(reason) {
      ui.setConnection("off");
      ui.toast(reason === "invalid-room" ? "Ungültiger Raum-Link" : "Verbindung abgelehnt");
    },
  });
  net.connect();

  function locUpdate(pos: Position): PeerUpdate {
    return { k: "loc", seed, lat: pos.lat, lng: pos.lng, acc: pos.acc, hdg: pos.hdg, at: Date.now() };
  }

  function startSharing(): void {
    if (!("geolocation" in navigator)) {
      ui.toast("Dieses Gerät kann keinen Standort teilen");
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
        markers.upsert(seed, self, pos, Date.now(), true);
        roster.set(seed, { color: self.color, name: `${self.name} (du)` });
        refreshRoster();
        if (!centeredOnSelf) {
          map.easeTo({ center: [pos.lng, pos.lat], zoom: 15, duration: 900 });
          centeredOnSelf = true;
        }
        void net.broadcast(locUpdate(pos));
      },
      (err) => {
        stopSharing();
        ui.toast(
          err.code === err.PERMISSION_DENIED
            ? "Standortfreigabe wurde abgelehnt"
            : "Standort nicht verfügbar"
        );
      },
      { enableHighAccuracy: true, maximumAge: 3000, timeout: 12000 }
    );
    ui.setSharing(true);
  }

  function stopSharing(): void {
    if (watchId !== null) {
      navigator.geolocation.clearWatch(watchId);
      watchId = null;
    }
    if (lastPos) void net.broadcast({ k: "stop", seed });
    lastPos = null;
    markers.remove("self");
    roster.delete("self");
    refreshRoster();
    ui.setSharing(false);
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
