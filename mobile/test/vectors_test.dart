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
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:cryptography/cryptography.dart';
import 'package:herebee/core/avatar.dart';
import 'package:herebee/core/crypto.dart';
import 'package:herebee/core/names.dart';
import 'package:herebee/core/rng.dart';
import 'package:herebee/features/map/menu_layout.dart';

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
        final packed = b64urlToBytes(m['ciphertext'] as String);
        expect(packed.length - 12 - 16, padBlock, reason: 'one pad block');
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

  group('shared messages', () {
    for (final v in vectors['sharedMessages'] as List<dynamic>) {
      test('sanitizes ${jsonEncode(v['input'])}', () {
        expect(sanitizeSharedMessage(v['input']), v['output']);
      });
    }
  });

  group('per-room seeds', () {
    for (final v in vectors['roomSeeds'] as List<dynamic>) {
      test('derives the seed for room ${v['roomId']}', () async {
        expect(await deriveRoomSeed(v['device'] as String, v['roomId'] as String), v['seed']);
      });
    }
  });

  group('bee menu layout', () {
    Offset pt(dynamic p) => Offset((p['x'] as num).toDouble(), (p['y'] as num).toDouble());
    MenuChoice? choiceOf(dynamic c) =>
        c == null ? null : MenuChoice(c['dir'] as int, c['turn'] as int, c['dist'] as int);
    for (final v in vectors['menuLayout'] as List<dynamic>) {
      final input = v['input'];
      test(
          'places the menu for a bee at ${jsonEncode(input['anchor'])}, bubble ${input['bubble']}, '
          'count ${input['count'] ?? 3}, previous ${jsonEncode(input['previous'])}', () {
        final b = input['bounds'];
        final got = layoutMenu(
          anchor: pt(input['anchor']),
          bounds: Rect.fromLTRB((b['left'] as num).toDouble(), (b['top'] as num).toDouble(),
              (b['right'] as num).toDouble(), (b['bottom'] as num).toDouble()),
          beeRadius: (input['beeRadius'] as num).toDouble(),
          bubble: (input['bubble'] as num).toDouble(),
          box: Size((input['box']['w'] as num).toDouble(), (input['box']['h'] as num).toDouble()),
          previous: choiceOf(input['previous']),
          count: (input['count'] as int?) ?? 3,
          outer: input['outer'] == null
              ? null
              : Rect.fromLTRB(
                  (input['outer']['left'] as num).toDouble(),
                  (input['outer']['top'] as num).toDouble(),
                  (input['outer']['right'] as num).toDouble(),
                  (input['outer']['bottom'] as num).toDouble()),
        );
        final want = v['output'];
        final wantBubbles = [for (final p in want['bubbles'] as List<dynamic>) pt(p)];
        expect(got.bubbles.length, wantBubbles.length, reason: 'bubble count');
        for (var i = 0; i < wantBubbles.length; i++) {
          expect((got.bubbles[i] - wantBubbles[i]).distance, lessThan(1e-6), reason: 'bubble $i');
        }
        expect((got.box - pt(want['box'])).distance, lessThan(1e-6), reason: 'box');
        expect(got.choice, choiceOf(want['choice']), reason: 'choice');
      });
    }

    test('springs towards its target exactly like the web', () {
      final spring = vectors['menuSpring'];
      final target = pt(spring['target']);
      final dt = (spring['dt'] as num).toDouble();
      var s = Spring.zero;
      var i = 0;
      for (final want in spring['states'] as List<dynamic>) {
        while (i < (want['step'] as int)) {
          s = springStep(s, target, dt);
          i++;
        }
        expect((s.position - pt(want)).distance, lessThan(1e-6), reason: 'position #$i');
        expect((Offset(s.vx, s.vy) - Offset((want['vx'] as num).toDouble(), (want['vy'] as num).toDouble())).distance,
            lessThan(1e-6),
            reason: 'velocity #$i');
        expect(springSettled(s, target), want['settled'], reason: 'settled #$i');
      }
    });
  });
}

String _hex(List<int> bytes) =>
    bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

Future<String> _sha256(String s) async =>
    _hex((await Sha256().hash(utf8.encode(s))).bytes);
