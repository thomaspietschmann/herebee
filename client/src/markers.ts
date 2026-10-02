/**
 * Marker manager. Renders one avatar marker per peer and expresses "freshness"
 * purely visually from the last-fix timestamp:
 *   fresh (<45s): full colour + pulse · stale (45s–2min): fading + "no signal" ·
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
import {
  layoutMenu,
  springSettled,
  springStep,
  type Bounds,
  type MenuChoice,
  type Point,
  type Spring,
} from "./menu-layout.js";

// 45 s, not 15: the native apps send only every 30 s while resting in the
// background, and one missed heartbeat must not read as "no signal". Keep in
// sync with freshFor in mobile/lib/core/peer_state.dart.
const FRESH_MS = 45_000;
const STALE_MS = 120_000;
export const LINGER_MS = 20 * 60_000; // keep a silent peer this long after its last fix
export const MSG_TTL_MS = 10 * 60_000;

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
  sayEl: HTMLElement;
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

export function relTime(ageMs: number): string {
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
  onZoom: () => void;
  onToggleFollow: () => void;
  onSay?: () => void;
}

const DISC_RADIUS = 21;
const BUBBLE_SIZE = 46;
const EMOJI_ONLY = /^(?:\p{Extended_Pictographic}|\p{Emoji_Component}|\u200D|\uFE0F|\s){1,24}$/u;

function isEmojiOnly(text: string): boolean {
  if (!EMOJI_ONLY.test(text) || !/\p{Extended_Pictographic}/u.test(text)) return false;
  const graphemes = [...new Intl.Segmenter(undefined, { granularity: "grapheme" }).segment(text.replace(/\s/g, ""))];
  return graphemes.length <= 3;
}

class MenuMotion {
  private springs: Spring[];
  private targets: Point[];
  private frame = 0;
  private last = 0;

  constructor(
    private readonly nodes: HTMLElement[],
    private readonly instant: boolean
  ) {
    this.springs = nodes.map(() => ({ x: 0, y: 0, vx: 0, vy: 0 }));
    this.targets = nodes.map(() => ({ x: 0, y: 0 }));
    this.apply();
  }

  get count(): number {
    return this.nodes.length;
  }

  aim(targets: Point[]): void {
    this.targets = targets;
    if (this.instant) {
      this.springs = targets.map((p) => ({ x: p.x, y: p.y, vx: 0, vy: 0 }));
      this.apply();
      return;
    }
    if (this.frame) return;
    this.last = performance.now();
    this.frame = requestAnimationFrame(this.tick);
  }

  stop(): void {
    cancelAnimationFrame(this.frame);
    this.frame = 0;
  }

  private tick = (now: number): void => {
    const dt = (now - this.last) / 1000;
    this.last = now;
    this.springs = this.springs.map((s, i) => springStep(s, this.targets[i], dt));
    const settled = this.springs.every((s, i) => springSettled(s, this.targets[i]));
    if (settled) this.springs = this.targets.map((p) => ({ x: p.x, y: p.y, vx: 0, vy: 0 }));
    this.apply();
    this.frame = settled ? 0 : requestAnimationFrame(this.tick);
  };

  private apply(): void {
    this.nodes.forEach((node, i) => {
      node.style.setProperty("--x", `${this.springs[i].x}px`);
      node.style.setProperty("--y", `${this.springs[i].y}px`);
    });
  }
}

export class MarkerManager {
  private entries = new Map<string, Entry>();
  // Only one marker's action menu is open at a time. Its DOM lives as a child
  // of that marker's `.mk` element (see build()), so it pans/zooms with the
  // map for free; we just track a reference to remove/animate it.
  private menuEl: HTMLElement | null = null;
  private menuSeed: string | null = null;
  private menuMotion: MenuMotion | null = null;
  private menuChoice: MenuChoice | null = null;
  // MapLibre stacks marker elements by DOM order; without an explicit z-index a
  // bee (and its fanned-out menu) can sit behind an overlapping neighbour. We
  // bump the active one with a monotonically increasing z-index so the most
  // recently raised marker is always on top.
  private zTop = 1;

  constructor(
    private readonly map: MlMap,
    private readonly onSelect?: (seed: string) => void,
    private readonly menuBounds?: () => Bounds
  ) {
    map.on("move", () => this.layoutOpenMenu());
    window.addEventListener("resize", () => this.layoutOpenMenu());
  }

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
      <div class="mk-say-dot" aria-hidden="true"></div>
      <div class="mk-say" aria-hidden="true"></div>
      <div class="mk-label"></div>`;
    const label = el.querySelector<HTMLElement>(".mk-label")!;
    const arrow = el.querySelector<HTMLElement>(".mk-arrow")!;
    const sayEl = el.querySelector<HTMLElement>(".mk-say")!;
    label.textContent = identity.name;
    return { el, label, arrow, sayEl };
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
      if (this.menuSeed === id) this.layoutOpenMenu();
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

  say(seed: string, text: string | null, pop: boolean): void {
    const e = this.entries.get(seed);
    if (!e) return;
    if (!text) {
      e.el.classList.remove("has-say", "say-pop");
      e.sayEl.textContent = "";
      return;
    }
    e.sayEl.textContent = text;
    e.sayEl.classList.toggle("is-emoji", isEmojiOnly(text));
    e.el.classList.add("has-say");
    if (pop) {
      e.el.classList.remove("say-pop");
      void e.el.offsetWidth;
      e.el.classList.add("say-pop");
      this.raise(seed);
    }
  }

  isOnScreen(seed: string): boolean {
    const e = this.entries.get(seed);
    if (!e) return false;
    const p = this.map.project([e.pos.lng, e.pos.lat]);
    const c = this.map.getContainer();
    return p.x >= 0 && p.y >= 0 && p.x <= c.clientWidth && p.y <= c.clientHeight;
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
    if (this.menuSeed) this.entries.get(this.menuSeed)?.el.classList.remove("has-menu");
    const motion = this.menuMotion;
    this.menuEl = null;
    this.menuSeed = null;
    this.menuMotion = null;
    this.menuChoice = null;
    el.classList.remove("is-open");
    if (window.matchMedia("(prefers-reduced-motion: reduce)").matches) {
      motion?.stop();
      el.remove();
      return;
    }
    if (motion) motion.aim(Array.from({ length: motion.count }, () => ({ x: 0, y: 0 })));
    const done = () => {
      motion?.stop();
      el.remove();
    };
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
      <button type="button" class="mk-bubble mk-bubble-zoom" aria-label="${t("menuZoomAria")}">🔍</button>
      <button type="button" class="mk-bubble mk-bubble-follow${actions.following ? " is-following" : ""}" aria-label="${actions.following ? t("menuUnfollow") : t("menuFollow")}">📍</button>
      ${actions.onSay ? `<button type="button" class="mk-bubble mk-bubble-say" aria-label="${t("menuSayAria")}">💬</button>` : ""}
      <div class="mk-infobox"><div class="mk-infobox-name"></div><div class="mk-infobox-lines">${actions.infoHtml}</div></div>`;
    div.querySelector<HTMLElement>(".mk-infobox-name")!.textContent = e.identity.name;
    const on = (sel: string, fn: () => void) =>
      div.querySelector(sel)!.addEventListener("click", (ev) => {
        ev.stopPropagation();
        fn();
      });
    on(".mk-bubble-rename", actions.onRename);
    on(".mk-bubble-zoom", actions.onZoom);
    on(".mk-bubble-follow", actions.onToggleFollow);
    if (actions.onSay) on(".mk-bubble-say", actions.onSay);
    e.el.appendChild(div);
    e.el.classList.add("has-menu");
    this.menuEl = div;
    this.menuSeed = seed;
    this.menuMotion = new MenuMotion(
      [...div.querySelectorAll<HTMLElement>(".mk-bubble, .mk-infobox")],
      window.matchMedia("(prefers-reduced-motion: reduce)").matches
    );
    this.raise(seed); // an active bee + its fanned-out menu must sit above neighbours
    requestAnimationFrame(() => {
      div.classList.add("is-open");
      this.layoutOpenMenu();
    });
  }

  private layoutOpenMenu(): void {
    const el = this.menuEl;
    const e = this.menuSeed ? this.entries.get(this.menuSeed) : undefined;
    if (!el || !e) return;
    const rect = this.map.getContainer().getBoundingClientRect();
    const p = this.map.project([e.pos.lng, e.pos.lat]);
    const anchor = { x: rect.left + p.x, y: rect.top + p.y };
    if (anchor.x < rect.left || anchor.x > rect.right || anchor.y < rect.top || anchor.y > rect.bottom) {
      this.closeMenu();
      return;
    }
    const box = el.querySelector<HTMLElement>(".mk-infobox")!;
    const bounds = this.menuBounds?.() ?? {
      left: rect.left + 8,
      top: rect.top + 8,
      right: rect.right - 8,
      bottom: rect.bottom - 8,
    };
    const layout = layoutMenu({
      anchor,
      bounds,
      beeRadius: DISC_RADIUS,
      bubble: BUBBLE_SIZE,
      box: { w: box.offsetWidth, h: box.offsetHeight },
      previous: this.menuChoice,
      count: el.querySelectorAll(".mk-bubble").length,
      outer: { left: rect.left + 8, top: rect.top + 8, right: rect.right - 8, bottom: rect.bottom - 8 },
    });
    this.menuChoice = layout.choice;
    this.menuMotion?.aim([...layout.bubbles, layout.box]);
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
    const info = this.menuEl.querySelector(".mk-infobox-lines");
    if (info) info.innerHTML = actions.infoHtml;
    const followBtn = this.menuEl.querySelector(".mk-bubble-follow");
    if (followBtn) {
      followBtn.classList.toggle("is-following", actions.following);
      followBtn.setAttribute("aria-label", t(actions.following ? "menuUnfollow" : "menuFollow"));
    }
    this.layoutOpenMenu();
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
    if (this.menuSeed === seed) {
      const nameEl = this.menuEl?.querySelector<HTMLElement>(".mk-infobox-name");
      if (nameEl) nameEl.textContent = name;
    }
  }

  remove(id: string): void {
    const e = this.entries.get(id);
    if (!e) return;
    // Its DOM (including any open menu) is going away with the marker itself —
    // just drop our reference rather than animate a close.
    if (this.menuSeed === id) {
      this.menuMotion?.stop();
      this.menuEl = null;
      this.menuSeed = null;
      this.menuMotion = null;
      this.menuChoice = null;
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
