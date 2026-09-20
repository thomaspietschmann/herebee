/// Seed -> identity. Avatars are little bee faces assembled entirely offline
/// from SVG building blocks.
///
/// Port of `client/src/avatar.ts`. The same seed must yield the same bee here
/// and in the browser, so the ORDER of `pick()` calls is part of the format and
/// the emitted string must match character for character.
///
/// Two JavaScript behaviours are reproduced explicitly, because Dart's defaults
/// differ and the difference is invisible until a peer sees the wrong bee:
///  - `Math.round` rounds halves toward +infinity; Dart's `round()` rounds them
///    away from zero. `_jsRound` below matches JavaScript.
///  - JavaScript prints an integral double without a decimal point ("39"),
///    Dart prints "39.0". `_n` below matches JavaScript.
library;

import 'dart:math' as math;

import 'rng.dart';

class Identity {
  const Identity({
    required this.seed,
    required this.name,
    required this.hue,
    required this.color,
    required this.svg,
  });

  final String seed;
  final String name;
  final int hue;

  /// Primary identity colour (HSL) — used for the marker ring.
  final String color;

  /// Inline SVG string of the creature on a transparent background.
  final String svg;
}

/// JavaScript's `Math.round`: floor(x + 0.5), i.e. halves go toward +infinity.
int _jsRound(num x) => (x + 0.5).floor();

/// JavaScript's number-to-string: integral values print without a decimal point.
String _n(num v) {
  if (v is int) return v.toString();
  final d = v.toDouble();
  if (d.isFinite && d == d.truncateToDouble()) return d.toInt().toString();
  return d.toString();
}

String hslToCss(num h, num s, num l) =>
    'hsl(${_jsRound(h)} ${_jsRound(s)}% ${_jsRound(l)}%)';

/// Golden-angle-nudged hue from the seed, spread across the wheel.
int hueFromSeed(String seed) {
  final h = cyrb53(seed, 0x9e37);
  return _jsRound(((h % 100000) / 100000) * 360 * 1.618) % 360;
}

/// Hardcoded hues, hand-ordered so any run of consecutive entries stays far
/// apart on the colour wheel. Assigned by first-seen order rather than by a seed
/// hash, so people present at the same time stay visually distinct.
const List<int> huePalette = [210, 25, 145, 335, 55, 265, 185, 5, 100, 300, 40, 230];

/// Palette hue for the Nth participant seen (by first-seen order), wrapping.
int hueFromIndex(int i) => huePalette[i % huePalette.length];

class _BeePalette {
  const _BeePalette({
    required this.body,
    required this.bodyShade,
    required this.dark,
    required this.stripe,
    required this.wing,
    required this.accent,
    required this.blush,
    required this.white,
  });

  final String body, bodyShade, dark, stripe, wing, accent, blush, white;
}

_BeePalette _palette(num hue, double Function() rng) {
  final gold = 43 + _jsRound(rng() * 8 - 4);
  final glow = 58 + _jsRound(rng() * 6);
  return _BeePalette(
    body: hslToCss(gold, 96, glow),
    bodyShade: hslToCss(gold + 4, 90, 48),
    dark: '#17120d',
    stripe: '#24170e',
    wing: 'rgba(253, 253, 251, 0.72)',
    accent: hslToCss(hue, 78, 59),
    blush: '#ff7f90',
    white: '#fdfdfb',
  );
}

class _BodyShape {
  const _BodyShape(this.rx, this.ry, this.cy, this.tilt);
  final int rx, ry, cy, tilt;
}

const List<_BodyShape> _bodyShapes = [
  _BodyShape(30, 34, 56, -3), // upright oval
  _BodyShape(34, 31, 57, 0), // round
  _BodyShape(36, 29, 58, 3), // chubby
  _BodyShape(28, 36, 55, 0), // tall
];

String _wings(String kind, _BeePalette p) {
  final slim = kind == 'slim';
  final wide = kind == 'wide';
  final rx = slim ? 11 : (wide ? 16 : 13);
  final ry = slim ? 22 : (wide ? 19 : 21);
  return '<g fill="${p.wing}" stroke="${p.dark}" stroke-width="1.6">\n'
      '    <ellipse cx="27" cy="43" rx="$rx" ry="$ry" transform="rotate(-27 27 43)"/>\n'
      '    <ellipse cx="73" cy="43" rx="$rx" ry="$ry" transform="rotate(27 73 43)"/></g>';
}

String _antennae(String kind, _BeePalette p) {
  final curl = kind == 'curly';
  final high = kind == 'high';
  final left = curl ? 'M42 29 q-10 -9 -7 -20' : (high ? 'M41 29 q-8 -13 -5 -23' : 'M42 29 q-7 -10 -10 -18');
  final right = curl ? 'M58 29 q10 -9 7 -20' : (high ? 'M59 29 q8 -13 5 -23' : 'M58 29 q7 -10 10 -18');
  final lcx = curl ? 35 : (high ? 36 : 32);
  final rcx = curl ? 65 : (high ? 64 : 68);
  final cy = curl ? 9 : (high ? 6 : 11);
  return '<g stroke="${p.dark}" stroke-width="3" stroke-linecap="round" fill="${p.accent}">\n'
      '    <path d="$left" fill="none"/><circle cx="$lcx" cy="$cy" r="4.5"/>\n'
      '    <path d="$right" fill="none"/><circle cx="$rcx" cy="$cy" r="4.5"/></g>';
}

String _body(_BeePalette p, _BodyShape s) =>
    '<ellipse cx="50" cy="${s.cy}" rx="${s.rx}" ry="${s.ry}" transform="rotate(${s.tilt} 50 ${s.cy})" fill="${p.body}" stroke="${p.dark}" stroke-width="3"/>';

String _stripes(String kind, _BeePalette p, _BodyShape s, String clipId) {
  final tilt = kind == 'tilt' ? -8 : (kind == 'tilt2' ? 8 : 0);
  if (kind == 'wave') {
    return '<g clip-path="url(#$clipId)" fill="none" stroke="${p.stripe}" stroke-width="7" stroke-linecap="round" opacity="0.92">\n'
        '      <path d="M17 ${s.cy + 6} q17 8 33 0 t33 0"/>\n'
        '      <path d="M17 ${s.cy + 22} q17 8 33 0 t33 0"/></g>';
  }
  final triple = kind == 'triple'
      ? '<rect x="17" y="${s.cy + 32}" width="66" height="7" rx="3.5"/>'
      : '';
  return '<g clip-path="url(#$clipId)" fill="${p.stripe}" opacity="0.92" transform="rotate($tilt 50 ${s.cy})">\n'
      '    <rect x="13" y="${s.cy + 1}" width="74" height="8" rx="4"/>\n'
      '    <rect x="13" y="${s.cy + 17}" width="74" height="8" rx="4"/>\n'
      '    $triple</g>';
}

String _facePatch(String kind, _BeePalette p) {
  if (kind == 'none') return '';
  if (kind == 'muzzle') {
    return '<ellipse cx="50" cy="63" rx="18" ry="14" fill="${p.bodyShade}" opacity="0.36"/>';
  }
  return '<path d="M28 47 q22 -15 44 0 q-5 21 -22 21 q-17 0 -22 -21Z" fill="${p.white}" opacity="0.18"/>';
}

String _eyes(String kind, _BeePalette p, double Function() rng) {
  final dx = (rng() * 4 - 2).toStringAsFixed(1);
  final dy = (rng() * 3 - 1).toStringAsFixed(1);
  final dxN = double.parse(dx);
  final dyN = double.parse(dy);
  String eye(num cx, num r, num pr) =>
      '<circle cx="${_n(cx)}" cy="47" r="${_n(r)}" fill="${p.white}" stroke="${p.dark}" stroke-width="1.6"/>'
      '<circle cx="${_n(cx + dxN)}" cy="${_n(47 + dyN)}" r="${_n(pr)}" fill="${p.dark}"/>'
      '<circle cx="${_n(cx - r / 3)}" cy="44" r="${_n(math.max(1.2, pr / 3))}" fill="${p.white}" opacity="0.9"/>';
  if (kind == 'big') return eye(39, 11, 5.4) + eye(61, 11, 5.4);
  if (kind == 'wide') return eye(35, 8.8, 4.2) + eye(65, 8.8, 4.2);
  if (kind == 'sleepy') {
    return '<path d="M31 47 q8 6 16 0 M53 47 q8 6 16 0" fill="none" stroke="${p.dark}" stroke-width="3" stroke-linecap="round"/>';
  }
  if (kind == 'wink') {
    return '${eye(38, 9.5, 4.7)}<path d="M55 47 q6 5 13 0" fill="none" stroke="${p.dark}" stroke-width="3" stroke-linecap="round"/>';
  }
  return eye(39, 9.8, 4.8) + eye(61, 9.8, 4.8);
}

String _mouth(String kind, _BeePalette p) {
  if (kind == 'o') return '<ellipse cx="50" cy="67" rx="4.5" ry="5.5" fill="${p.dark}"/>';
  if (kind == 'tiny') {
    return '<path d="M45 67 q5 4 10 0" fill="none" stroke="${p.dark}" stroke-width="2.5" stroke-linecap="round"/>';
  }
  if (kind == 'tongue') {
    return '<path d="M41 66 q9 9 18 0" fill="none" stroke="${p.dark}" stroke-width="3" stroke-linecap="round"/><ellipse cx="50" cy="72" rx="4" ry="3" fill="${p.blush}"/>';
  }
  if (kind == 'flat') {
    return '<line x1="44" y1="68" x2="56" y2="68" stroke="${p.dark}" stroke-width="3" stroke-linecap="round"/>';
  }
  return '<path d="M40 66 q10 10 20 0" fill="none" stroke="${p.dark}" stroke-width="3" stroke-linecap="round"/>';
}

String _cheeks(_BeePalette p) =>
    '<g fill="${p.blush}" opacity="0.68"><ellipse cx="32" cy="61" rx="5" ry="3.4"/><ellipse cx="68" cy="61" rx="5" ry="3.4"/></g>';

String _accent(String kind, _BeePalette p) {
  if (kind == 'pin') {
    return '<g transform="translate(50 28) scale(.72)" fill="${p.accent}" stroke="${p.dark}" stroke-width="2.2"><path d="M0 -10c6 0 10 4 10 9 0 7-10 17-10 17S-10 6-10-1c0-5 4-9 10-9Z"/><circle cx="0" cy="-1" r="3.5" fill="${p.white}"/></g>';
  }
  if (kind == 'spark') {
    return '<path d="M50 20 l3 7 7 3 -7 3 -3 7 -3 -7 -7 -3 7 -3Z" fill="${p.accent}" stroke="${p.dark}" stroke-width="1.6" stroke-linejoin="round"/>';
  }
  if (kind == 'dot') {
    return '<circle cx="50" cy="27" r="4.5" fill="${p.accent}" stroke="${p.dark}" stroke-width="1.8"/>';
  }
  return '';
}

/// Deterministic bee-face SVG for a seed. [hue] overrides the seed-derived hue
/// (identity colour) while the shape/pattern stay driven by the seed.
String creatureSvg(String seed, [int? hue]) {
  final rng = mulberry32(cyrb53(seed, 0x1234));
  final p = _palette(hue ?? hueFromSeed(seed), rng);
  final shape = pick(rng, _bodyShapes);
  final wingK = pick(rng, const ['classic', 'classic', 'wide', 'slim']);
  final stripeK = pick(rng, const ['straight', 'straight', 'triple', 'tilt', 'tilt2', 'wave']);
  final patchK = pick(rng, const ['none', 'none', 'muzzle', 'shine']);
  final eye = pick(rng, const ['two', 'two', 'big', 'wide', 'sleepy', 'wink']);
  final mouthK = pick(rng, const ['smile', 'smile', 'o', 'tiny', 'tongue', 'flat']);
  final antennaK = pick(rng, const ['classic', 'classic', 'curly', 'high']);
  final accentK = pick(rng, const ['none', 'none', 'none', 'pin', 'spark', 'dot']);
  final hasCheeks = rng() < 0.62;
  final clipId = 'c${(cyrb53(seed) % 1000000000).toRadixString(36)}';

  return '<svg viewBox="0 0 100 100" xmlns="http://www.w3.org/2000/svg">'
      '<defs><clipPath id="$clipId"><ellipse cx="50" cy="${shape.cy}" rx="${shape.rx}" ry="${shape.ry}"/></clipPath></defs>'
      '${_wings(wingK, p)}'
      '${_antennae(antennaK, p)}'
      '${_body(p, shape)}'
      '${_stripes(stripeK, p, shape, clipId)}'
      '${_facePatch(patchK, p)}'
      '${_accent(accentK, p)}'
      '${hasCheeks ? _cheeks(p) : ''}'
      '${_eyes(eye, p, rng)}'
      '${_mouth(mouthK, p)}'
      '</svg>';
}

/// Build the full identity for a seed (used for self and every peer).
Identity identityFromSeed(String seed, String name, [int? hue]) {
  final h = hue ?? hueFromSeed(seed);
  return Identity(
    seed: seed,
    name: name,
    hue: h,
    color: hslToCss(h, 72, 56),
    svg: creatureSvg(seed, h),
  );
}
