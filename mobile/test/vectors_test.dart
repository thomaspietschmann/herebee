/// Conformance against shared/vectors.json — the same file the web code is
/// tested against by `npm run test:vectors`.
///
/// A failure here means this app would behave differently from the browser for
/// the same room or the same person. Both are invisible at runtime: a wrong
/// derivation joins a different, valid, empty room, and a wrong PRNG draws a
/// different bee. That is why these are pinned rather than eyeballed.
library;

import 'dart:convert';
import 'package:cryptography/cryptography.dart' show Sha256;
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:cryptography/cryptography.dart';
import 'package:herebee/core/avatar.dart';
import 'package:herebee/core/crypto.dart';
import 'package:herebee/core/names.dart';
import 'package:herebee/core/rng.dart';

Map<String, dynamic> loadVectors() {
  final file = File('../shared/vectors.json');
  if (!file.existsSync()) {
    throw StateError('shared/vectors.json not found; run `npm run vectors` in the repo root');
  }
  return jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
}

void main() {
  final vectors = loadVectors();

  group('crypto', () {
    final crypto = vectors['crypto'] as Map<String, dynamic>;

    for (final entry in crypto['rooms'] as List<dynamic>) {
      final r = entry as Map<String, dynamic>;
      test('room derivation for ${r['roomId']}', () async {
        final keys = await deriveRoomKeys(r['secret'] as String);
        expect(keys.roomId, r['roomId'], reason: 'roomId');
        expect(await isValidRoomId(keys.roomId), isTrue, reason: 'checksum verifies');

        // The first 16 raw bytes of the id are the HKDF "room-id" material.
        final material = b64urlToBytes(keys.roomId).sublist(0, 16);
        expect(_hex(material), r['idMaterialHex'], reason: 'room-id material');

        // The AES key must be the exact bytes the browser derives, or the two
        // sides would each encrypt something the other cannot read.
        expect(_hex(await keys.key.extractBytes()), r['aesKeyHex'], reason: 'aes key');
      });
    }

    for (final entry in crypto['messages'] as List<dynamic>) {
      final m = entry as Map<String, dynamic>;
      final seed = (m['plaintext'] as Map<String, dynamic>)['seed'];
      test('decrypts browser ciphertext for seed "$seed"', () async {
        final keys = await deriveRoomKeys(m['secret'] as String);
        expect(keys.roomId, m['roomId']);
        // The direction that proves interoperability: read what the browser wrote.
        expect(await decryptJson(keys.key, m['ciphertext'] as String), m['plaintext']);
        // And the reverse, via a round trip (a fresh IV makes the bytes differ).
        final again = await encryptJson(keys.key, m['plaintext']);
        expect(await decryptJson(keys.key, again), m['plaintext']);
      });
    }

    test('rejects invalid room ids', () async {
      for (final bad in crypto['invalidRoomIds'] as List<dynamic>) {
        expect(await isValidRoomId(bad as String), isFalse, reason: bad);
      }
    });

    test('a foreign key does not decrypt', () async {
      final rooms = crypto['rooms'] as List<dynamic>;
      final a = await deriveRoomKeys((rooms[0] as Map<String, dynamic>)['secret'] as String);
      final b = await deriveRoomKeys((rooms[1] as Map<String, dynamic>)['secret'] as String);
      final blob = await encryptJson(a.key, {'k': 'stop', 'seed': 'x'});
      expect(await decryptJson(b.key, blob), isNull);
    });

    test('garbage decrypts to null rather than throwing', () async {
      final keys = await deriveRoomKeys((crypto['rooms'] as List<dynamic>).first['secret'] as String);
      for (final junk in ['', 'not-base64url!!', 'AAAA', 'a' * 64]) {
        expect(await decryptJson(keys.key, junk), isNull, reason: junk);
      }
    });
  });

  group('identity', () {
    for (final entry in vectors['identity'] as List<dynamic>) {
      final v = entry as Map<String, dynamic>;
      final seed = v['seed'] as String;
      test('seed "$seed"', () async {
        expect(germanName(seed), v['nameDe'], reason: 'German name');
        expect(englishName(seed), v['nameEn'], reason: 'English name');
        expect(hueFromSeed(seed), v['hueFromSeed'], reason: 'hue');
        expect(hslToCss(v['hueFromSeed'] as int, 72, 56), v['colorFromSeed'], reason: 'colour');
        expect(await _sha256(creatureSvg(seed)), v['svgSha256Default'], reason: 'bee SVG (seed hue)');
        expect(await _sha256(creatureSvg(seed, 210)), v['svgSha256Hue210'], reason: 'bee SVG (hue 210)');
      });
    }

    test('full SVG matches the browser character for character', () {
      // Hashes tell you THAT something diverged; these samples let a human see
      // WHERE, which matters because the SVG is assembled from a dozen pieces.
      for (final entry in vectors['svgSamples'] as List<dynamic>) {
        final s = entry as Map<String, dynamic>;
        expect(creatureSvg(s['seed'] as String), s['svg'], reason: s['seed'] as String);
      }
    });

    test('hue palette and first-seen assignment are unchanged', () {
      final constants = vectors['constants'] as Map<String, dynamic>;
      expect(huePalette, (constants['huePalette'] as List<dynamic>).cast<int>());
      expect(
        List<int>.generate(8, hueFromIndex),
        (constants['hueFromIndexFirst8'] as List<dynamic>).cast<int>(),
      );
    });
  });

  group('rng', () {
    for (final entry in vectors['rng'] as List<dynamic>) {
      final v = entry as Map<String, dynamic>;
      final seed = v['seed'] as String;
      test('seed "$seed"', () {
        expect(cyrb53(seed), v['cyrb53'], reason: 'cyrb53');
        expect(cyrb53(seed, 0x9e37), v['cyrb53Seed0x9e37'], reason: 'cyrb53 seeded 0x9e37');
        expect(cyrb53(seed, 0x1234), v['cyrb53Seed0x1234'], reason: 'cyrb53 seeded 0x1234');
        final gen = mulberry32(cyrb53(seed));
        final got = List<double>.generate(5, (_) => gen());
        final want = (v['mulberry32First5'] as List<dynamic>).cast<num>().map((n) => n.toDouble()).toList();
        expect(got, want, reason: 'mulberry32 stream');
      });
    }
  });

  group('shared names', () {
    for (final v in vectors['sharedNames'] as List<dynamic>) {
      test('sanitizes ${jsonEncode(v['input'])}', () {
        expect(sanitizeSharedName(v['input']), v['output']);
      });
    }
  });
}

String _hex(List<int> bytes) =>
    bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

Future<String> _sha256(String s) async =>
    _hex((await Sha256().hash(utf8.encode(s))).bytes);
