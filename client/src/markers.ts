/**
 * Marker manager. Renders one avatar marker per peer and expresses "freshness"
 * purely visually from the last-fix timestamp:
 *   fresh (<15s): full colour + pulse · stale (15s–2min): fading + "no signal" ·
 *   ghost (>2min): greyed at last known spot, "no signal for a while".
 * Separately, a marker can be flagged `offline` when the peer's relay
 * connection is known to have actually dropped (see main.ts's onLeft), which
 * overrides the label with an explicit "offline" — otherwise a stationary-but-
 * still-connected peer and a genuinely disconnected one look identical.
 * A peer is only removed when it ACTIVELY stops sharing. If its signal is merely
 * lost (tab closed, connection dropped, long tunnel), the ghost lingers at its
 * last known spot for up to LINGER_MS (20 min) and then disappears on its own.
 * Markers are keyed by identity seed, so a reconnect updates the same marker
 * instead of spawning a duplicate.
 */
import maplibregl, { type Map as MlMap, type Marker } from "maplibre-gl";
import type { Identity } from "./avatar.js";
import type { Position } from "./types.js";
import { t } from "./i18n.js";

const FRESH_MS = 15_000;
const STALE_MS = 120_000;
const LINGER_MS = 20 * 60_000; // keep a silent peer this long after its last fix

// GPS `heading` is noise at low speed (it can swing wildly while stationary or
// shuffling in place), so the arrow only shows once the fix reports genuine
// movement. ~1.5 m/s is a slow walk — comfortably above GPS jitter.
const MIN_ARROW_SPEED_MS = 1.5;

export type Tier = "fresh" | "stale" | "ghost";

interface Entry {
  marker: Marker;
  el: HTMLElement;
  label: HTMLElement;
  arrow: HTMLElement;
  identity: Identity;
  pos: Position;
  at: number;
  self: boolean;
  // True once we know this peer's relay connection actually dropped (see
  // main.ts onLeft), as opposed to merely not having sent a fix in a while.
  // Cleared the moment a fresh "loc" update arrives — that only happens over a
  // live connection, so it doubles as an online signal.
  offline: boolean;
}

function tierOf(age: number): Tier {
  if (age >= STALE_MS) return "ghost";
  if (age >= FRESH_MS) return "stale";
  return "fresh";
}

function relTime(ageMs: number): string {
  if (ageMs < 5_000) return t("justNow");
  if (ageMs < 60_000) return t("secsAgo", { n: Math.round(ageMs / 1000) });
  return t("minsAgo", { n: Math.round(ageMs / 60_000) });
}

/** Status label appended to a marker's name, or null when nothing's amiss. */
function statusSuffix(offline: boolean, tier: Tier, age: number): string | null {
  if (offline) return t("offlineStatus");
  if (tier === "fresh") return null;
  return t(tier === "ghost" ? "noSignalLong" : "noSignal", { t: relTime(age) });
}

/** Content + callbacks for the two action bubbles and info box shown on a
 *  marker click; see MarkerManager.openMenu. */
export interface MenuActions {
  following: boolean;
  infoHtml: string;
  onRename: () => void;
  onToggleFollow: () => void;
}

export class MarkerManager {
  private entries = new Map<string, Entry>();
  // Only one marker's action menu is open at a time. Its DOM lives as a child
  // of that marker's `.mk` element (see build()), so it pans/zooms with the
  // map for free; we just track a reference to remove/animate it.
  private menuEl: HTMLElement | null = null;
  private menuSeed: string | null = null;
  // MapLibre stacks marker elements by DOM order; without an explicit z-index a
  // bee (and its fanned-out menu) can sit behind an overlapping neighbour. We
  // bump the active one with a monotonically increasing z-index so the most
  // recently raised marker is always on top.
  private zTop = 1;

  constructor(
    private readonly map: MlMap,
    private readonly onSelect?: (seed: string) => void
  ) {}

  private build(
    identity: Identity,
    self: boolean
  ): Omit<Entry, "identity" | "pos" | "at" | "self" | "marker" | "offline"> {
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
      e = { marker, ...parts, identity, pos, at, self, offline: false };
      this.entries.set(id, e);
    } else {
      e.pos = pos;
      e.at = at;
      e.offline = false; // a fresh fix only arrives over a live connection
      e.marker.setLngLat([pos.lng, pos.lat]);
    }
    const moving = pos.spd != null && !Number.isNaN(pos.spd) && pos.spd >= MIN_ARROW_SPEED_MS;
    if (moving && pos.hdg != null && !Number.isNaN(pos.hdg)) {
      e.arrow.style.opacity = "1";
      e.arrow.style.transform = `rotate(${pos.hdg}deg)`;
    } else {
      e.arrow.style.opacity = "0";
    }
    this.refresh(id, e);
  }

  private refresh(_id: string, e: Entry): void {
    const age = Date.now() - e.at;
    const tier = tierOf(age);
    e.el.classList.remove("is-fresh", "is-stale", "is-ghost", "is-offline");
    e.el.classList.add(`is-${tier}`);
    if (e.offline) e.el.classList.add("is-offline");
    const suffix = statusSuffix(e.offline, tier, age);
    e.label.textContent = suffix ? `${e.identity.name} · ${suffix}` : e.identity.name;
  }

  /** Mark a peer's relay connection as dropped (or restored). No-op for
   *  unknown/self markers — see main.ts's onLeft/onPeer wiring. */
  setOffline(seed: string, offline: boolean): void {
    const e = this.entries.get(seed);
    if (!e || e.self || e.offline === offline) return;
    e.offline = offline;
    this.refresh(seed, e);
  }

  /** Everything an info box needs for one marker, or null if it's not on the map. */
  status(seed: string): { at: number; offline: boolean; tier: Tier; lastSeen: string } | null {
    const e = this.entries.get(seed);
    if (!e) return null;
    const age = Date.now() - e.at;
    return { at: e.at, offline: e.offline, tier: tierOf(age), lastSeen: relTime(age) };
  }

  /** The seed whose action menu is open, or null if none is. */
  openSeed(): string | null {
    return this.menuSeed;
  }

  /** Close whatever menu is open, animating it back into the avatar. No-op if none is open. */
  closeMenu(): void {
    const el = this.menuEl;
    if (!el) return;
    this.menuEl = null;
    this.menuSeed = null;
    el.classList.remove("is-open");
    if (window.matchMedia("(prefers-reduced-motion: reduce)").matches) {
      el.remove();
      return;
    }
    const done = () => el.remove();
    el.addEventListener("transitionend", done, { once: true });
    setTimeout(done, 300); // safety net if transitionend never fires
  }

  /** Open the two action bubbles + info box for one marker, closing any other
   *  open menu first. Bubbles/box are built fresh each time and animate out
   *  from the avatar's center (see .mk-menu/.mk-bubble/.mk-infobox in CSS). */
  openMenu(seed: string, actions: MenuActions): void {
    this.closeMenu();
    const e = this.entries.get(seed);
    if (!e) return;
    const div = document.createElement("div");
    div.className = "mk-menu";
    div.innerHTML = `
      <button type="button" class="mk-bubble mk-bubble-rename" aria-label="${t("menuRenameAria")}">✏️</button>
      <button type="button" class="mk-bubble mk-bubble-follow${actions.following ? " is-following" : ""}" aria-label="${actions.following ? t("menuUnfollow") : t("menuFollow")}">📍</button>
      <div class="mk-infobox">${actions.infoHtml}</div>`;
    div.querySelector(".mk-bubble-rename")!.addEventListener("click", (ev) => {
      ev.stopPropagation();
      actions.onRename();
    });
    div.querySelector(".mk-bubble-follow")!.addEventListener("click", (ev) => {
      ev.stopPropagation();
      actions.onToggleFollow();
    });
    e.el.appendChild(div);
    this.menuEl = div;
    this.menuSeed = seed;
    this.raise(seed); // an active bee + its fanned-out menu must sit above neighbours
    requestAnimationFrame(() => div.classList.add("is-open"));
  }

  /** Lift a marker above any overlapping ones so it (and its menu) are on top
   *  and clickable. Monotonic, so the latest raise always wins. */
  raise(seed: string): void {
    const e = this.entries.get(seed);
    if (!e) return;
    e.el.style.zIndex = String(++this.zTop);
  }

  /** Refresh the open menu's info box and follow state in place (no re-animation).
   *  No-op unless `seed` is the currently open menu. */
  updateMenu(seed: string, actions: Pick<MenuActions, "following" | "infoHtml">): void {
    if (this.menuSeed !== seed || !this.menuEl) return;
    const info = this.menuEl.querySelector(".mk-infobox");
    if (info) info.innerHTML = actions.infoHtml;
    const followBtn = this.menuEl.querySelector(".mk-bubble-follow");
    if (followBtn) {
      followBtn.classList.toggle("is-following", actions.following);
      followBtn.setAttribute("aria-label", t(actions.following ? "menuUnfollow" : "menuFollow"));
    }
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
    // Its DOM (including any open menu) is going away with the marker itself —
    // just drop our reference rather than animate a close.
    if (this.menuSeed === id) {
      this.menuEl = null;
      this.menuSeed = null;
    }
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
