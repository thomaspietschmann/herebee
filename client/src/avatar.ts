/**
 * Seed -> identity. Avatars are little bee faces assembled entirely offline from
 * SVG building blocks: body, wings, stripes, eyes, mouth, antennae and a tiny
 * optional accent. The same seed always yields the same bee, so peers render
 * each other identically without server state or third-party avatar services.
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

// --- bee building blocks ----------------------------------------------------

interface BeePalette {
  body: string;
  bodyShade: string;
  dark: string;
  stripe: string;
  wing: string;
  accent: string;
  blush: string;
  white: string;
}

function palette(hue: number, rng: () => number): BeePalette {
  const gold = 43 + Math.round(rng() * 8 - 4);
  const glow = 58 + Math.round(rng() * 6);
  return {
    body: hslToCss(gold, 96, glow),
    bodyShade: hslToCss(gold + 4, 90, 48),
    dark: "#17120d",
    stripe: "#24170e",
    wing: "rgba(253, 253, 251, 0.72)",
    accent: hslToCss(hue, 78, 59),
    blush: "#ff7f90",
    white: "#fdfdfb",
  };
}

const BODY_SHAPES = [
  { rx: 30, ry: 34, cy: 56, tilt: -3 }, // upright oval
  { rx: 34, ry: 31, cy: 57, tilt: 0 }, // round
  { rx: 36, ry: 29, cy: 58, tilt: 3 }, // chubby
  { rx: 28, ry: 36, cy: 55, tilt: 0 }, // tall
] as const;

function wings(kind: string, p: BeePalette): string {
  const slim = kind === "slim";
  const wide = kind === "wide";
  const rx = slim ? 11 : wide ? 16 : 13;
  const ry = slim ? 22 : wide ? 19 : 21;
  return `<g fill="${p.wing}" stroke="${p.dark}" stroke-width="1.6">
    <ellipse cx="27" cy="43" rx="${rx}" ry="${ry}" transform="rotate(-27 27 43)"/>
    <ellipse cx="73" cy="43" rx="${rx}" ry="${ry}" transform="rotate(27 73 43)"/></g>`;
}

function antennae(kind: string, p: BeePalette): string {
  const curl = kind === "curly";
  const high = kind === "high";
  const left = curl ? "M42 29 q-10 -9 -7 -20" : high ? "M41 29 q-8 -13 -5 -23" : "M42 29 q-7 -10 -10 -18";
  const right = curl ? "M58 29 q10 -9 7 -20" : high ? "M59 29 q8 -13 5 -23" : "M58 29 q7 -10 10 -18";
  return `<g stroke="${p.dark}" stroke-width="3" stroke-linecap="round" fill="${p.accent}">
    <path d="${left}" fill="none"/><circle cx="${curl ? 35 : high ? 36 : 32}" cy="${curl ? 9 : high ? 6 : 11}" r="4.5"/>
    <path d="${right}" fill="none"/><circle cx="${curl ? 65 : high ? 64 : 68}" cy="${curl ? 9 : high ? 6 : 11}" r="4.5"/></g>`;
}

function body(p: BeePalette, s: (typeof BODY_SHAPES)[number]): string {
  return `<ellipse cx="50" cy="${s.cy}" rx="${s.rx}" ry="${s.ry}" transform="rotate(${s.tilt} 50 ${s.cy})" fill="${p.body}" stroke="${p.dark}" stroke-width="3"/>`;
}

function stripes(kind: string, p: BeePalette, s: (typeof BODY_SHAPES)[number], clipId: string): string {
  const tilt = kind === "tilt" ? -8 : kind === "tilt2" ? 8 : 0;
  const wave = kind === "wave";
  if (wave) {
    return `<g clip-path="url(#${clipId})" fill="none" stroke="${p.stripe}" stroke-width="7" stroke-linecap="round" opacity="0.92">
      <path d="M17 ${s.cy + 6} q17 8 33 0 t33 0"/>
      <path d="M17 ${s.cy + 22} q17 8 33 0 t33 0"/></g>`;
  }
  return `<g clip-path="url(#${clipId})" fill="${p.stripe}" opacity="0.92" transform="rotate(${tilt} 50 ${s.cy})">
    <rect x="13" y="${s.cy + 1}" width="74" height="8" rx="4"/>
    <rect x="13" y="${s.cy + 17}" width="74" height="8" rx="4"/>
    ${kind === "triple" ? `<rect x="17" y="${s.cy + 32}" width="66" height="7" rx="3.5"/>` : ""}</g>`;
}

function facePatch(kind: string, p: BeePalette): string {
  if (kind === "none") return "";
  if (kind === "muzzle")
    return `<ellipse cx="50" cy="63" rx="18" ry="14" fill="${p.bodyShade}" opacity="0.36"/>`;
  return `<path d="M28 47 q22 -15 44 0 q-5 21 -22 21 q-17 0 -22 -21Z" fill="${p.white}" opacity="0.18"/>`;
}

function eyes(kind: string, p: BeePalette, rng: () => number): string {
  const dx = (rng() * 4 - 2).toFixed(1);
  const dy = (rng() * 3 - 1).toFixed(1);
  const eye = (cx: number, r: number, pr: number) =>
    `<circle cx="${cx}" cy="47" r="${r}" fill="${p.white}" stroke="${p.dark}" stroke-width="1.6"/>` +
    `<circle cx="${cx + +dx}" cy="${47 + +dy}" r="${pr}" fill="${p.dark}"/>` +
    `<circle cx="${cx - r / 3}" cy="${44}" r="${Math.max(1.2, pr / 3)}" fill="${p.white}" opacity="0.9"/>`;
  if (kind === "big") return eye(39, 11, 5.4) + eye(61, 11, 5.4);
  if (kind === "wide") return eye(35, 8.8, 4.2) + eye(65, 8.8, 4.2);
  if (kind === "sleepy")
    return `<path d="M31 47 q8 6 16 0 M53 47 q8 6 16 0" fill="none" stroke="${p.dark}" stroke-width="3" stroke-linecap="round"/>`;
  if (kind === "wink") return eye(38, 9.5, 4.7) + `<path d="M55 47 q6 5 13 0" fill="none" stroke="${p.dark}" stroke-width="3" stroke-linecap="round"/>`;
  return eye(39, 9.8, 4.8) + eye(61, 9.8, 4.8);
}

function mouth(kind: string, p: BeePalette): string {
  if (kind === "o") return `<ellipse cx="50" cy="67" rx="4.5" ry="5.5" fill="${p.dark}"/>`;
  if (kind === "tiny") return `<path d="M45 67 q5 4 10 0" fill="none" stroke="${p.dark}" stroke-width="2.5" stroke-linecap="round"/>`;
  if (kind === "tongue")
    return `<path d="M41 66 q9 9 18 0" fill="none" stroke="${p.dark}" stroke-width="3" stroke-linecap="round"/><ellipse cx="50" cy="72" rx="4" ry="3" fill="${p.blush}"/>`;
  if (kind === "flat") return `<line x1="44" y1="68" x2="56" y2="68" stroke="${p.dark}" stroke-width="3" stroke-linecap="round"/>`;
  return `<path d="M40 66 q10 10 20 0" fill="none" stroke="${p.dark}" stroke-width="3" stroke-linecap="round"/>`;
}

function cheeks(p: BeePalette): string {
  return `<g fill="${p.blush}" opacity="0.68"><ellipse cx="32" cy="61" rx="5" ry="3.4"/><ellipse cx="68" cy="61" rx="5" ry="3.4"/></g>`;
}

function accent(kind: string, p: BeePalette): string {
  if (kind === "pin")
    return `<g transform="translate(50 28) scale(.72)" fill="${p.accent}" stroke="${p.dark}" stroke-width="2.2"><path d="M0 -10c6 0 10 4 10 9 0 7-10 17-10 17S-10 6-10-1c0-5 4-9 10-9Z"/><circle cx="0" cy="-1" r="3.5" fill="${p.white}"/></g>`;
  if (kind === "spark")
    return `<path d="M50 20 l3 7 7 3 -7 3 -3 7 -3 -7 -7 -3 7 -3Z" fill="${p.accent}" stroke="${p.dark}" stroke-width="1.6" stroke-linejoin="round"/>`;
  if (kind === "dot") return `<circle cx="50" cy="27" r="4.5" fill="${p.accent}" stroke="${p.dark}" stroke-width="1.8"/>`;
  return "";
}

/** Deterministic bee-face SVG for a seed. */
export function creatureSvg(seed: string): string {
  const rng = mulberry32(cyrb53(seed, 0x1234));
  const p = palette(hueFromSeed(seed), rng);
  const shape = pick(rng, BODY_SHAPES);
  const wingK = pick(rng, ["classic", "classic", "wide", "slim"]);
  const stripeK = pick(rng, ["straight", "straight", "triple", "tilt", "tilt2", "wave"]);
  const patchK = pick(rng, ["none", "none", "muzzle", "shine"]);
  const eye = pick(rng, ["two", "two", "big", "wide", "sleepy", "wink"]);
  const mouthK = pick(rng, ["smile", "smile", "o", "tiny", "tongue", "flat"]);
  const antennaK = pick(rng, ["classic", "classic", "curly", "high"]);
  const accentK = pick(rng, ["none", "none", "none", "pin", "spark", "dot"]);
  const hasCheeks = rng() < 0.62;
  const clipId = "c" + (cyrb53(seed) % 1e9).toString(36);

  return (
    `<svg viewBox="0 0 100 100" xmlns="http://www.w3.org/2000/svg">` +
    `<defs><clipPath id="${clipId}"><ellipse cx="50" cy="${shape.cy}" rx="${shape.rx}" ry="${shape.ry}"/></clipPath></defs>` +
    wings(wingK, p) +
    antennae(antennaK, p) +
    body(p, shape) +
    stripes(stripeK, p, shape, clipId) +
    facePatch(patchK, p) +
    accent(accentK, p) +
    (hasCheeks ? cheeks(p) : "") +
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
