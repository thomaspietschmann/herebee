/**
 * Seed -> identity. Avatars are generated fully offline with DiceBear's `shapes`
 * style (CC0): geometric building blocks that recombine into an endless set of
 * distinct avatars. Each member also gets a stable identifying hue so peers are
 * easy to tell apart on the map.
 */
import { createAvatar } from "@dicebear/core";
import { shapes } from "@dicebear/collection";
import { cyrb53 } from "./rng.js";

export interface Identity {
  seed: string;
  name: string;
  hue: number;
  /** Primary identity colour (HSL). */
  color: string;
  /** Inline <svg> string of the avatar on a transparent background. */
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

export function avatarSvg(seed: string): string {
  return createAvatar(shapes, {
    seed,
    size: 64,
    backgroundColor: ["transparent"],
    radius: 0,
  }).toString();
}

/** Build the full identity for a seed (used for self and every peer). */
export function identityFromSeed(seed: string, name: string): Identity {
  const hue = hueFromSeed(seed);
  return {
    seed,
    name,
    hue,
    color: hslToCss(hue, 72, 56),
    svg: avatarSvg(seed),
  };
}
