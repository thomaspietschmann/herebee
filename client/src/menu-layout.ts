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
const ARC_DIRECTIONS = [-90, -45, -135, 0, 180, 45, 135, 90];
const BOX_TURNS = [180, 135, -135, 90, -90];

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

function shiftInside(boxes: Box[], bounds: Bounds): Box[] {
  const left = Math.min(...boxes.map((b) => b.x - b.w / 2));
  const right = Math.max(...boxes.map((b) => b.x + b.w / 2));
  const top = Math.min(...boxes.map((b) => b.y - b.h / 2));
  const bottom = Math.max(...boxes.map((b) => b.y + b.h / 2));
  const dx =
    left < bounds.left
      ? bounds.left - left
      : right > bounds.right
        ? Math.max(bounds.right - right, bounds.left - left)
        : 0;
  const dy =
    top < bounds.top
      ? bounds.top - top
      : bottom > bounds.bottom
        ? Math.max(bounds.bottom - bottom, bounds.top - top)
        : 0;
  return boxes.map((b) => ({ ...b, x: b.x + dx, y: b.y + dy }));
}

function deflate(bounds: Bounds, by: number): Bounds {
  return { left: bounds.left + by, top: bounds.top + by, right: bounds.right - by, bottom: bounds.bottom - by };
}

export function layoutMenu(input: MenuLayoutInput): MenuLayout {
  const { anchor, bounds, beeRadius, bubble, box } = input;
  const previous = input.previous ?? null;
  const count = input.count ?? 3;
  const ring = beeRadius + GAP + bubble / 2;
  const step = Math.max(SPREAD, deg(2 * Math.asin(Math.min(1, (bubble + BUBBLE_MARGIN) / (2 * ring)))));
  const boxDistances = [beeRadius + GAP, beeRadius + GAP + bubble + GAP];
  const strict = deflate(bounds, HYSTERESIS);

  const bubblesAt = (dir: number): Box[] =>
    Array.from({ length: count }, (_, i) => dir + (i - (count - 1) / 2) * step).map((a) => ({
      x: anchor.x + Math.cos(rad(a)) * ring,
      y: anchor.y + Math.sin(rad(a)) * ring,
      w: bubble,
      h: bubble,
    }));

  const boxAt = (dir: number, dist: number): Box => {
    const ux = Math.cos(rad(dir));
    const uy = Math.sin(rad(dir));
    return {
      x: anchor.x + ux * dist + (ux * box.w) / 2,
      y: anchor.y + uy * dist + (uy * box.h) / 2,
      w: box.w,
      h: box.h,
    };
  };

  const total = (bubbles: Box[], b: Box, within: Bounds): number =>
    bubbles.reduce((s, x) => s + overflow(x, within), 0) + overflow(b, within);

  let passedPrevious = previous === null;
  let best: { bubbles: Box[]; box: Box; choice: MenuChoice } | null = null;
  let bestOverflow = Infinity;
  for (let d = 0; d < ARC_DIRECTIONS.length; d++) {
    const dir = ARC_DIRECTIONS[d];
    const bubbles = bubblesAt(dir);
    for (let t = 0; t < BOX_TURNS.length; t++) {
      for (let k = 0; k < boxDistances.length; k++) {
        const b = boxAt(dir + BOX_TURNS[t], boxDistances[k]);
        const choice = { dir: d, turn: t, dist: k };
        if (previous !== null && previous.dir === d && previous.turn === t && previous.dist === k) {
          passedPrevious = true;
        }
        if (bubbles.some((x) => overlaps(x, b, 4))) continue;
        const within = passedPrevious ? bounds : strict;
        if (total(bubbles, b, within) === 0) return result(anchor, bubbles, b, choice);
        const over = total(bubbles, b, bounds);
        if (over < bestOverflow) {
          bestOverflow = over;
          best = { bubbles, box: b, choice };
        }
      }
    }
  }
  const shifted = shiftInside([...best!.bubbles, best!.box], bounds);
  return result(anchor, shifted.slice(0, count), shifted[count], best!.choice);
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
