/**
 * Marker manager. Renders one avatar marker per peer and expresses "freshness"
 * purely visually from the last-fix timestamp:
 *   fresh (<15s): full colour + pulse · stale (15s–2min): fading + "vor X" ·
 *   ghost (>2min): greyed at last known spot.
 * A peer is only removed when it ACTIVELY stops sharing. If its signal is merely
 * lost (tab closed, connection dropped, long tunnel), the ghost lingers at its
 * last known spot for up to LINGER_MS (20 min) and then disappears on its own.
 * Markers are keyed by identity seed, so a reconnect updates the same marker
 * instead of spawning a duplicate.
 */
import maplibregl, { type Map as MlMap, type Marker } from "maplibre-gl";
import type { Identity } from "./avatar.js";
import type { Position } from "./types.js";

const FRESH_MS = 15_000;
const STALE_MS = 120_000;
const LINGER_MS = 20 * 60_000; // keep a silent peer this long after its last fix

interface Entry {
  marker: Marker;
  el: HTMLElement;
  label: HTMLElement;
  arrow: HTMLElement;
  identity: Identity;
  pos: Position;
  at: number;
  self: boolean;
}

function relTime(ageMs: number): string {
  if (ageMs < 5_000) return "gerade eben";
  if (ageMs < 60_000) return `vor ${Math.round(ageMs / 1000)} s`;
  return `vor ${Math.round(ageMs / 60_000)} min`;
}

export class MarkerManager {
  private entries = new Map<string, Entry>();

  constructor(
    private readonly map: MlMap,
    private readonly onSelect?: (seed: string) => void
  ) {}

  private build(identity: Identity, self: boolean): Omit<Entry, "identity" | "pos" | "at" | "self" | "marker"> {
    const el = document.createElement("div");
    el.className = "mk" + (self ? " mk-self" : "");
    el.style.setProperty("--c", identity.color);
    el.innerHTML = `
      <div class="mk-pulse"></div>
      <div class="mk-arrow"></div>
      <div class="mk-disc">${identity.svg}</div>
      <div class="mk-label"></div>`;
    const label = el.querySelector<HTMLElement>(".mk-label")!;
    const arrow = el.querySelector<HTMLElement>(".mk-arrow")!;
    label.textContent = identity.name;
    return { el, label, arrow };
  }

  upsert(id: string, identity: Identity, pos: Position, at: number, self = false): void {
    let e = this.entries.get(id);
    if (!e) {
      const parts = this.build(identity, self);
      parts.el.addEventListener("click", (ev) => {
        ev.stopPropagation();
        this.onSelect?.(id); // id === identity seed
      });
      const marker = new maplibregl.Marker({ element: parts.el, anchor: "center" })
        .setLngLat([pos.lng, pos.lat])
        .addTo(this.map);
      e = { marker, ...parts, identity, pos, at, self };
      this.entries.set(id, e);
    } else {
      e.pos = pos;
      e.at = at;
      e.marker.setLngLat([pos.lng, pos.lat]);
    }
    if (pos.hdg != null && !Number.isNaN(pos.hdg)) {
      e.arrow.style.opacity = "1";
      e.arrow.style.transform = `rotate(${pos.hdg}deg)`;
    } else {
      e.arrow.style.opacity = "0";
    }
    this.refresh(id, e);
  }

  private refresh(_id: string, e: Entry): void {
    const age = Date.now() - e.at;
    let tier = "fresh";
    if (age >= STALE_MS) tier = "ghost";
    else if (age >= FRESH_MS) tier = "stale";
    e.el.classList.remove("is-fresh", "is-stale", "is-ghost");
    e.el.classList.add(`is-${tier}`);
    e.label.textContent = tier === "fresh" ? e.identity.name : `${e.identity.name} · ${relTime(age)}`;
  }

  /** Called ~1×/s to age markers and drop peers silent longer than LINGER_MS. */
  tick(): string[] {
    const removed: string[] = [];
    for (const [id, e] of this.entries) {
      if (!e.self && Date.now() - e.at > LINGER_MS) {
        this.remove(id);
        removed.push(id);
        continue;
      }
      this.refresh(id, e);
    }
    return removed;
  }

  has(id: string): boolean {
    return this.entries.has(id);
  }

  /** A marker's [lng, lat], or null if that peer isn't on the map. */
  positionOf(id: string): [number, number] | null {
    const e = this.entries.get(id);
    return e ? [e.pos.lng, e.pos.lat] : null;
  }

  /** Bounds covering every marker, or null if there are none (nothing shared). */
  bounds(): maplibregl.LngLatBounds | null {
    let b: maplibregl.LngLatBounds | null = null;
    for (const e of this.entries.values()) {
      const ll: [number, number] = [e.pos.lng, e.pos.lat];
      b = b ? b.extend(ll) : new maplibregl.LngLatBounds(ll, ll);
    }
    return b;
  }

  /** Update a marker's displayed name (local rename), keeping it in sync now. */
  rename(seed: string, name: string): void {
    const e = this.entries.get(seed);
    if (!e) return;
    e.identity.name = name;
    this.refresh(seed, e);
  }

  remove(id: string): void {
    const e = this.entries.get(id);
    if (!e) return;
    e.marker.remove();
    this.entries.delete(id);
  }

  count(): number {
    return this.entries.size;
  }

  /** Snapshot of every marker (id, position, last-fix time, self flag) for
   *  handing a freshly-opened follower tab the current state in one shot. */
  dump(): Array<{ id: string; pos: Position; at: number; self: boolean }> {
    return [...this.entries].map(([id, e]) => ({ id, pos: e.pos, at: e.at, self: e.self }));
  }
}
