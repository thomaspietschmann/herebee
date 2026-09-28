import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:herebee/app_config.dart';
import 'package:herebee/core/crypto.dart';
import 'package:herebee/core/peer_state.dart';
import 'package:herebee/core/storage.dart';
import 'package:herebee/core/types.dart';
import 'package:shared_preferences/shared_preferences.dart';

LocUpdate loc(int at) =>
    LocUpdate(seed: 'p', lat: 1, lng: 2, acc: null, hdg: null, spd: null, at: at);

void main() {
  group('padding', () {
    test('pads with spaces to the next multiple of 256 bytes', () {
      expect(padPlaintext(List<int>.filled(1, 0x7b)).length, 256);
      expect(padPlaintext(List<int>.filled(255, 0x7b)).length, 256);
      expect(padPlaintext(List<int>.filled(256, 0x7b)).length, 256);
      expect(padPlaintext(List<int>.filled(257, 0x7b)).length, 512);
      final padded = padPlaintext(utf8.encode('{"a":1}'));
      expect(padded.sublist(7).every((b) => b == 0x20), isTrue);
    });

    test('padded ciphertexts hide the length and still decrypt', () async {
      final keys = await deriveRoomKeys(generateSecret());
      final short = await encryptJson(keys.key, {'t': 'loc', 'n': 'A'});
      final long = await encryptJson(keys.key, {'t': 'loc', 'n': 'A much longer name than the other'});
      expect(b64urlToBytes(short).length, ivBytes + 256 + tagBytes);
      expect(b64urlToBytes(long).length, b64urlToBytes(short).length);
      expect(await decryptJson(keys.key, long), {'t': 'loc', 'n': 'A much longer name than the other'});
    });

    test('trailing spaces are tolerated by jsonDecode', () {
      expect(jsonDecode('{"a":1}${' ' * 249}'), {'a': 1});
    });
  });

  group('peer timestamps', () {
    final now = DateTime.fromMillisecondsSinceEpoch(1700000000000);
    final nowMs = now.millisecondsSinceEpoch;

    test('a timestamp from the future is clamped to now + 5 s', () {
      final peers = PeerStore()..upsert(loc(nowMs + 3600 * 1000), now: now);
      expect(peers['p']!.at, nowMs + 5000);
    });

    test('a timestamp within the skew allowance is kept', () {
      final peers = PeerStore()..upsert(loc(nowMs + 4000), now: now);
      expect(peers['p']!.at, nowMs + 4000);
    });

    test('an update older than the linger window is dropped', () {
      final peers = PeerStore()..upsert(loc(nowMs - lingerFor.inMilliseconds - 1), now: now);
      expect(peers['p'], isNull);
      peers.upsert(loc(nowMs), now: now);
      peers.upsert(loc(nowMs - lingerFor.inMilliseconds - 1), now: now);
      expect(peers['p']!.at, nowMs, reason: 'a stale update must not rewind a live peer');
    });

    test('an update just inside the linger window is kept', () {
      final peers = PeerStore()..upsert(loc(nowMs - lingerFor.inMilliseconds), now: now);
      expect(peers['p']!.at, nowMs - lingerFor.inMilliseconds);
    });
  });

  group('reconnect token', () {
    test('is not persisted, stays stable per process, and old stored ones are removed', () async {
      SharedPreferences.setMockInitialValues({'herebee.cid': 'oldtoken'});
      final storage = await Storage.open();
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.containsKey('herebee.cid'), isFalse);
      final cid = await storage.cid();
      expect(cid, isNot('oldtoken'));
      expect(cid, matches(RegExp(r'^[0-9a-z]+$')));
      expect(await (await Storage.open()).cid(), cid);
      expect(prefs.getKeys().where((k) => prefs.getString(k) == cid), isEmpty);
    });
  });

  test('clientVersion matches the pubspec version', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    final version = RegExp(r'^version:\s*([^\s+]+)', multiLine: true).firstMatch(pubspec)!.group(1);
    expect(AppConfig.clientVersion, version);
  });
}
