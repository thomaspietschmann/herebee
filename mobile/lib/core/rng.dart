/// Deterministic, seed-driven helpers for avatars, names and colours.
///
/// A direct port of `client/src/rng.ts`. Every value here must match the
/// browser's output BIT FOR BIT: the same seed has to yield the same bee on a
/// phone and on a laptop, and nothing about the result is transmitted, so a
/// mismatch cannot be detected at runtime. `test/vectors_test.dart` pins it
/// against `shared/vectors.json`.
///
/// The subtlety is that JavaScript's bitwise operators coerce to 32 bits while
/// Dart's `int` is 64-bit. Every operation below therefore narrows explicitly;
/// dropping one of those calls silently produces different numbers.
library;

/// JavaScript's `Math.imul`: multiply as 32-bit signed, keep the low 32 bits.
///
/// Both operands are narrowed to signed 32 bits first, so the product is at most
/// 2^62 and cannot overflow Dart's 64-bit int. Masking to unsigned 32 bits
/// instead would allow a 2^64 product and silently wrong results.
int _imul(int a, int b) => (a.toSigned(32) * b.toSigned(32)).toSigned(32);

/// JavaScript's `>>>`: shift the value as unsigned 32 bits.
int _ushr(int value, int shift) => (value & 0xFFFFFFFF) >> shift;

/// cyrb53 — fast, well-distributed 53-bit string hash.
///
/// Iterates UTF-16 code units, exactly as JS's `charCodeAt` does, so astral
/// characters (an emoji, say) contribute two units on both platforms.
int cyrb53(String str, [int seed = 0]) {
  int h1 = 0xdeadbeef ^ seed;
  int h2 = 0x41c6ce57 ^ seed;
  for (int i = 0; i < str.length; i++) {
    final int ch = str.codeUnitAt(i);
    h1 = _imul(h1 ^ ch, 2654435761);
    h2 = _imul(h2 ^ ch, 1597334677);
  }
  h1 = _imul(h1 ^ _ushr(h1, 16), 2246822507);
  h1 = (h1 ^ _imul(h2 ^ _ushr(h2, 13), 3266489909)).toSigned(32);
  h2 = _imul(h2 ^ _ushr(h2, 16), 2246822507);
  h2 = (h2 ^ _imul(h1 ^ _ushr(h1, 13), 3266489909)).toSigned(32);
  return 4294967296 * (2097151 & (h2 & 0xFFFFFFFF)) + (h1 & 0xFFFFFFFF);
}

/// mulberry32 — tiny seeded PRNG returning floats in [0, 1).
double Function() mulberry32(int seed) {
  int a = seed & 0xFFFFFFFF;
  return () {
    a = (a + 0x6d2b79f5).toSigned(32);
    int t = _imul(a ^ _ushr(a, 15), (1 | a).toSigned(32));
    t = ((t + _imul(t ^ _ushr(t, 7), (61 | t).toSigned(32))).toSigned(32) ^ t).toSigned(32);
    return ((t ^ _ushr(t, 14)) & 0xFFFFFFFF) / 4294967296;
  };
}

double Function() rngFromSeed(String seed) => mulberry32(cyrb53(seed));

T pick<T>(double Function() rng, List<T> arr) => arr[(rng() * arr.length).floor()];
