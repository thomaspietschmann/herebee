import type { Map as MlMap } from "maplibre-gl";

export const FOLLOW_BURST_PX = 160;
const RUBBER_REACH = 48;

interface Pt {
  x: number;
  y: number;
}

export function followRubber(travel: Pt): Pt {
  const d = Math.hypot(travel.x, travel.y);
  if (d === 0) return { x: 0, y: 0 };
  const visible = RUBBER_REACH * (1 - 1 / ((d * 0.55) / RUBBER_REACH + 1));
  return { x: (travel.x / d) * visible, y: (travel.y / d) * visible };
}

export interface FollowDragHooks {
  isFollowing(): boolean;
  onActive(active: boolean): void;
  onStretch(progress: number): void;
  onBurst(): void;
  onSnapBack(): void;
}

export function attachFollowDrag(map: MlMap, hooks: FollowDragHooks): void {
  const el = map.getCanvasContainer();
  const pointers = new Map<number, Pt>();
  let start: Pt = { x: 0, y: 0 };
  let last: Pt = { x: 0, y: 0 };
  let applied: Pt = { x: 0, y: 0 };
  let burst = false;
  let multi = false;

  const local = (e: PointerEvent): Pt => {
    const r = el.getBoundingClientRect();
    return { x: e.clientX - r.left, y: e.clientY - r.top };
  };

  const shift = (dx: number, dy: number): void => {
    if (dx === 0 && dy === 0) return;
    const c = map.project(map.getCenter());
    map.jumpTo({ center: map.unproject([c.x - dx, c.y - dy]) });
  };

  const relax = (): void => {
    if (burst || (applied.x === 0 && applied.y === 0)) return;
    applied = { x: 0, y: 0 };
    hooks.onStretch(0);
    hooks.onSnapBack();
  };

  el.addEventListener("pointerdown", (e) => {
    if (!hooks.isFollowing() || (e.pointerType === "mouse" && e.button !== 0)) return;
    if ((e.target as Element).closest(".maplibregl-marker")) return;
    const p = local(e);
    pointers.set(e.pointerId, p);
    if (pointers.size === 1) {
      start = p;
      last = p;
      applied = { x: 0, y: 0 };
      burst = false;
      multi = false;
      hooks.onActive(true);
    } else {
      multi = true;
      relax();
    }
  });

  window.addEventListener("pointermove", (e) => {
    if (!pointers.has(e.pointerId)) return;
    const p = local(e);
    pointers.set(e.pointerId, p);
    if (multi) return;
    if (burst) {
      shift(p.x - last.x, p.y - last.y);
      last = p;
      return;
    }
    const travel = { x: p.x - start.x, y: p.y - start.y };
    const progress = Math.hypot(travel.x, travel.y) / FOLLOW_BURST_PX;
    if (progress >= 1) {
      burst = true;
      shift(travel.x - applied.x, travel.y - applied.y);
      applied = { x: 0, y: 0 };
      last = p;
      hooks.onStretch(0);
      hooks.onBurst();
      return;
    }
    const visible = followRubber(travel);
    shift(visible.x - applied.x, visible.y - applied.y);
    applied = visible;
    last = p;
    hooks.onStretch(progress);
  });

  const up = (e: PointerEvent): void => {
    if (!pointers.delete(e.pointerId) || pointers.size > 0) return;
    relax();
    burst = false;
    multi = false;
    hooks.onActive(false);
  };
  window.addEventListener("pointerup", up);
  window.addEventListener("pointercancel", up);
}
