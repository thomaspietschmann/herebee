export interface Point {
  x: number;
  y: number;
}

export interface Bounds {
  left: number;
  top: number;
  right: number;
  bottom: number;
}

export interface MenuChoice {
  dir: number;
  turn: number;
  dist: number;
}

export interface MenuLayoutInput {
  anchor: Point;
  bounds: Bounds;
  beeRadius: number;
  bubble: number;
  box: { w: number; h: number };
  previous?: MenuChoice | null;
  count?: number;
  outer?: Bounds | null;
}

export interface MenuLayout {
  bubbles: Point[];
  box: Point;
  choice: MenuChoice;
}

const SPREAD = 50;
const GAP = 10;
const BUBBLE_MARGIN = 4;
const HYSTERESIS = 12;
const ARC_STEP = 15;
const ARC_DIRECTIONS = [-90, ...Array.from({ length: 12 }, (_, i) => i + 1).flatMap((k) => (k === 12 ? [90] : [-90 + ARC_STEP * k, -90 - ARC_STEP * k]))];
const SIDES = [-90, 90, 180, 0];
const SLIDES = 3;

interface Box {
  x: number;
  y: number;
  w: number;
  h: number;
}

const rad = (deg: number): number => (deg * Math.PI) / 180;
const deg = (r: number): number => (r * 180) / Math.PI;

function overflow(b: Box, bounds: Bounds): number {
  return (
    Math.max(0, bounds.left - (b.x - b.w / 2)) +
    Math.max(0, b.x + b.w / 2 - bounds.right) +
    Math.max(0, bounds.top - (b.y - b.h / 2)) +
    Math.max(0, b.y + b.h / 2 - bounds.bottom)
  );
}

function overlaps(a: Box, b: Box, margin: number): boolean {
  return Math.abs(a.x - b.x) < (a.w + b.w) / 2 + margin && Math.abs(a.y - b.y) < (a.h + b.h) / 2 + margin;
}

function deflate(bounds: Bounds, by: number): Bounds {
  return { left: bounds.left + by, top: bounds.top + by, right: bounds.right - by, bottom: bounds.bottom - by };
}

function angleGap(a: number, b: number): number {
  const d = Math.abs((((a - b) % 360) + 360) % 360);
  return Math.min(d, 360 - d);
}

function clamp(v: number, lo: number, hi: number): number {
  return Math.min(Math.max(v, lo), hi);
}

export function layoutMenu(input: MenuLayoutInput): MenuLayout {
  const { anchor, bounds, beeRadius, bubble, box } = input;
  const previous = input.previous ?? null;
  const count = input.count ?? 3;
  const outer = input.outer ?? null;
  const ring = beeRadius + GAP + bubble / 2;
  const step = Math.max(SPREAD, deg(2 * Math.asin(Math.min(1, (bubble + BUBBLE_MARGIN) / (2 * ring)))));
  const boxDistances = [beeRadius + GAP, beeRadius + GAP + bubble + GAP];

  const bubblesAt = (dir: number): Box[] =>
    Array.from({ length: count }, (_, i) => dir + (i - (count - 1) / 2) * step).map((a) => ({
      x: anchor.x + Math.cos(rad(a)) * ring,
      y: anchor.y + Math.sin(rad(a)) * ring,
      w: bubble,
      h: bubble,
    }));

  const boxAt = (side: number, dist: number, slide: number, region: Bounds): Box => {
    const vertical = side === -90 || side === 90;
    const ux = Math.round(Math.cos(rad(side)));
    const uy = Math.round(Math.sin(rad(side)));
    const limit = Math.max(0, (vertical ? box.w : box.h) / 2 - beeRadius);
    const lo = vertical ? region.left + box.w / 2 - anchor.x : region.top + box.h / 2 - anchor.y;
    const hi = vertical ? region.right - box.w / 2 - anchor.x : region.bottom - box.h / 2 - anchor.y;
    const fit = clamp(lo > hi ? lo : clamp(0, lo, hi), -limit, limit);
    const s = slide === 0 ? fit : slide === 1 ? -limit : limit;
    return {
      x: anchor.x + ux * (dist + box.w / 2) + (vertical ? s : 0),
      y: anchor.y + uy * (dist + box.h / 2) + (vertical ? 0 : s),
      w: box.w,
      h: box.h,
    };
  };

  const total = (bubbles: Box[], b: Box, within: Bounds): number =>
    bubbles.reduce((s, x) => s + overflow(x, within), 0) + overflow(b, within);

  const regions = outer ? [bounds, outer] : [bounds];
  const last = regions[regions.length - 1];
  let best: { bubbles: Box[]; box: Box; choice: MenuChoice } | null = null;
  let bestOverflow = Infinity;
  for (let r = 0; r < regions.length; r++) {
    const region = regions[r];
    const strict = deflate(region, HYSTERESIS);
    let passedPrevious = previous === null;
    for (let d = 0; d < ARC_DIRECTIONS.length; d++) {
      const dir = ARC_DIRECTIONS[d];
      const bubbles = bubblesAt(dir);
      const sides = SIDES.map((side, i) => ({ side, i })).sort(
        (a, b) => angleGap(a.side, dir + 180) - angleGap(b.side, dir + 180) || a.i - b.i
      );
      for (const { side, i } of sides) {
        for (let k = 0; k < boxDistances.length; k++) {
          for (let v = 0; v < SLIDES; v++) {
            const choice = { dir: r * ARC_DIRECTIONS.length + d, turn: i * SLIDES + v, dist: k };
            if (previous !== null && previous.dir === choice.dir && previous.turn === choice.turn && previous.dist === k) {
              passedPrevious = true;
            }
            const within = passedPrevious ? region : strict;
            const b = boxAt(side, boxDistances[k], v, within);
            if (bubbles.some((x) => overlaps(x, b, 4))) continue;
            if (total(bubbles, b, within) === 0) return result(anchor, bubbles, b, choice);
            const over = total(bubbles, b, last);
            if (over < bestOverflow) {
              bestOverflow = over;
              best = { bubbles, box: b, choice };
            }
          }
        }
      }
    }
  }
  return result(anchor, best!.bubbles, best!.box, best!.choice);
}

function result(anchor: Point, bubbles: Box[], box: Box, choice: MenuChoice): MenuLayout {
  return {
    bubbles: bubbles.map((b) => ({ x: b.x - anchor.x, y: b.y - anchor.y })),
    box: { x: box.x - anchor.x, y: box.y - anchor.y },
    choice,
  };
}

export const SPRING_STIFFNESS = 260;
export const SPRING_DAMPING = 15;
const MAX_STEP = 1 / 30;

export interface Spring {
  x: number;
  y: number;
  vx: number;
  vy: number;
}

export function springStep(s: Spring, target: Point, dt: number): Spring {
  const h = Math.min(dt, MAX_STEP);
  const ax = SPRING_STIFFNESS * (target.x - s.x) - SPRING_DAMPING * s.vx;
  const ay = SPRING_STIFFNESS * (target.y - s.y) - SPRING_DAMPING * s.vy;
  const vx = s.vx + ax * h;
  const vy = s.vy + ay * h;
  return { x: s.x + vx * h, y: s.y + vy * h, vx, vy };
}

export function springSettled(s: Spring, target: Point): boolean {
  return (
    Math.abs(target.x - s.x) < 0.3 && Math.abs(target.y - s.y) < 0.3 && Math.abs(s.vx) < 3 && Math.abs(s.vy) < 3
  );
}
