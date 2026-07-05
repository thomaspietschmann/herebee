/**
 * Seed -> identity. Avatars are little "fantasy critters" assembled entirely
 * offline from building blocks — body, belly/pattern, eyes, mouth, antennae or
 * ears, optional wings and cheeks — driven by a seeded PRNG. The same seed always
 * yields the same creature, so peers render each other identically without any
 * server state or third-party avatar service.
 */
import { cyrb53, mulberry32, pick } from "./rng.js";

export interface Identity {
  seed: string;
  name: string;
  hue: number;
  /** Primary identity colour (HSL) — used for the marker ring. */
  color: string;
  /** Inline <svg> string of the creature on a transparent background. */
  svg: string;
}

export function hslToCss(h: number, s: number, l: number): string {
  return `hsl(${Math.round(h)} ${Math.round(s)}% ${Math.round(l)}%)`;
}

/** Golden-angle-nudged hue from the seed, spread across the wheel. */
export function hueFromSeed(seed: string): number {
  const h = cyrb53(seed, 0x9e37);
  return Math.round(((h % 100000) / 100000) * 360 * 1.618) % 360;
}

// --- building blocks --------------------------------------------------------

interface Palette {
  body: string;
  dark: string;
  belly: string;
  accent: string;
  white: string;
}

function palette(hue: number): Palette {
  return {
    body: hslToCss(hue, 66, 60),
    dark: hslToCss(hue, 55, 28),
    belly: hslToCss(hue, 62, 86),
    accent: hslToCss((hue + 45) % 360, 80, 62),
    white: "#fdfdfb",
  };
}

const BODY_SHAPES = [
  { rx: 33, ry: 32, cy: 56 }, // round
  { rx: 29, ry: 36, cy: 54 }, // egg
  { rx: 36, ry: 29, cy: 58 }, // wide
];

function wings(p: Palette): string {
  return `<g opacity="0.55" fill="${p.white}" stroke="${p.dark}" stroke-width="1.5">
    <ellipse cx="24" cy="46" rx="15" ry="21" transform="rotate(-22 24 46)"/>
    <ellipse cx="76" cy="46" rx="15" ry="21" transform="rotate(22 76 46)"/></g>`;
}

function body(p: Palette, s: (typeof BODY_SHAPES)[number]): string {
  return `<ellipse cx="50" cy="${s.cy}" rx="${s.rx}" ry="${s.ry}" fill="${p.body}" stroke="${p.dark}" stroke-width="3"/>`;
}

function pattern(kind: string, p: Palette, s: (typeof BODY_SHAPES)[number], clipId: string): string {
  if (kind === "belly")
    return `<ellipse cx="50" cy="${s.cy + 8}" rx="${s.rx * 0.6}" ry="${s.ry * 0.62}" fill="${p.belly}"/>`;
  if (kind === "spots")
    return `<g fill="${p.dark}" opacity="0.8"><circle cx="40" cy="${s.cy + 4}" r="4"/><circle cx="60" cy="${s.cy - 2}" r="3.5"/><circle cx="52" cy="${s.cy + 14}" r="4.5"/></g>`;
  if (kind === "stripes")
    return `<g clip-path="url(#${clipId})"><g fill="${p.dark}" opacity="0.85">
      <rect x="10" y="${s.cy - 2}" width="80" height="7"/><rect x="10" y="${s.cy + 12}" width="80" height="7"/></g></g>`;
  return "";
}

function eyes(kind: string, p: Palette, rng: () => number): string {
  const dx = (rng() * 4 - 2).toFixed(1);
  const dy = (rng() * 3 - 1).toFixed(1);
  const eye = (cx: number, r: number, pr: number) =>
    `<circle cx="${cx}" cy="48" r="${r}" fill="${p.white}" stroke="${p.dark}" stroke-width="1.5"/>` +
    `<circle cx="${cx + +dx}" cy="${48 + +dy}" r="${pr}" fill="${p.dark}"/>`;
  if (kind === "big") return eye(40, 12, 6) + eye(60, 12, 6);
  if (kind === "wide") return eye(35, 9, 4.5) + eye(65, 9, 4.5);
  if (kind === "sleepy")
    return `<path d="M31 48 q8 6 16 0 M53 48 q8 6 16 0" fill="none" stroke="${p.dark}" stroke-width="3" stroke-linecap="round"/>`;
  return eye(39, 10, 5) + eye(61, 10, 5); // two
}

function mouth(kind: string, p: Palette): string {
  if (kind === "o") return `<ellipse cx="50" cy="70" rx="4.5" ry="5.5" fill="${p.dark}"/>`;
  if (kind === "cat")
    return `<path d="M43 68 q4 5 7 0 q3 5 7 0" fill="none" stroke="${p.dark}" stroke-width="2.5" stroke-linecap="round"/>`;
  if (kind === "tongue")
    return `<path d="M41 67 q9 9 18 0" fill="none" stroke="${p.dark}" stroke-width="3" stroke-linecap="round"/><ellipse cx="50" cy="73" rx="4" ry="3" fill="#ff7a8a"/>`;
  if (kind === "flat") return `<line x1="44" y1="70" x2="56" y2="70" stroke="${p.dark}" stroke-width="3" stroke-linecap="round"/>`;
  return `<path d="M40 67 q10 10 20 0" fill="none" stroke="${p.dark}" stroke-width="3" stroke-linecap="round"/>`; // smile
}

function crown(kind: string, p: Palette): string {
  if (kind === "antennae")
    return `<g stroke="${p.dark}" stroke-width="3" stroke-linecap="round" fill="${p.accent}">
      <path d="M42 27 q-6 -10 -8 -16" fill="none"/><circle cx="33" cy="9" r="5"/>
      <path d="M58 27 q6 -10 8 -16" fill="none"/><circle cx="67" cy="9" r="5"/></g>`;
  if (kind === "ears")
    return `<g fill="${p.body}" stroke="${p.dark}" stroke-width="3"><circle cx="30" cy="30" r="9"/><circle cx="70" cy="30" r="9"/></g>`;
  if (kind === "horns")
    return `<g fill="${p.accent}" stroke="${p.dark}" stroke-width="2"><path d="M38 30 L34 14 L44 26 Z"/><path d="M62 30 L66 14 L56 26 Z"/></g>`;
  return "";
}

function cheeks(): string {
  return `<g fill="#ff9aa8" opacity="0.75"><ellipse cx="33" cy="62" rx="5" ry="3.5"/><ellipse cx="67" cy="62" rx="5" ry="3.5"/></g>`;
}

/** Deterministic creature SVG for a seed. */
export function creatureSvg(seed: string): string {
  const rng = mulberry32(cyrb53(seed, 0x1234));
  const p = palette(hueFromSeed(seed));
  const shape = pick(rng, BODY_SHAPES);
  const hasWings = rng() < 0.45;
  const pat = pick(rng, ["belly", "belly", "spots", "stripes", "none"]);
  const eye = pick(rng, ["two", "two", "big", "wide", "sleepy"]);
  const mouthK = pick(rng, ["smile", "smile", "o", "cat", "tongue", "flat"]);
  const crownK = pick(rng, ["antennae", "antennae", "ears", "horns", "none"]);
  const hasCheeks = rng() < 0.55;
  const clipId = "c" + (cyrb53(seed) % 1e9).toString(36);

  return (
    `<svg viewBox="0 0 100 100" xmlns="http://www.w3.org/2000/svg">` +
    `<defs><clipPath id="${clipId}"><ellipse cx="50" cy="${shape.cy}" rx="${shape.rx}" ry="${shape.ry}"/></clipPath></defs>` +
    (hasWings ? wings(p) : "") +
    crown(crownK, p) +
    body(p, shape) +
    pattern(pat, p, shape, clipId) +
    (hasCheeks ? cheeks() : "") +
    eyes(eye, p, rng) +
    mouth(mouthK, p) +
    `</svg>`
  );
}

/** Build the full identity for a seed (used for self and every peer). */
export function identityFromSeed(seed: string, name: string): Identity {
  const hue = hueFromSeed(seed);
  return {
    seed,
    name,
    hue,
    color: hslToCss(hue, 72, 56),
    svg: creatureSvg(seed),
  };
}
