/// Inbound validation. Every room member holds the same key, so a MALICIOUS
/// member can wrap arbitrary plaintext in a valid ciphertext. These cases are
/// the ones that would otherwise reach the map, the avatar generator or the
/// camera. Mirrors `validPeerUpdate` in client/src/net.ts.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:herebee/core/protocol.dart';
import 'package:herebee/core/types.dart';

Map<String, dynamic> loc({
  Object? seed = 'abc',
  Object? lat = 52.52,
  Object? lng = 13.405,
  Object? acc = 10,
  Object? hdg = 90,
  Object? spd = 2,
  Object? at = 1700000000000,
}) =>
    {'k': 'loc', 'seed': seed, 'lat': lat, 'lng': lng, 'acc': acc, 'hdg': hdg, 'spd': spd, 'at': at};

void main() {
  test('accepts a well-formed loc update', () {
    final u = validPeerUpdate(loc());
    expect(u, isA<LocUpdate>());
    expect((u! as LocUpdate).lat, 52.52);
  });

  test('accepts null for the optional fields', () {
    final u = validPeerUpdate(loc(acc: null, hdg: null, spd: null));
    expect(u, isA<LocUpdate>());
    expect((u! as LocUpdate).acc, isNull);
  });

  test('carries a shared name, cleaned, and drops only a bad one', () {
    final named = validPeerUpdate({...loc(), 'name': ' \u202eAnna '})! as LocUpdate;
    expect(named.name, 'Anna');
    final bad = validPeerUpdate({...loc(), 'name': 42});
    expect(bad, isA<LocUpdate>(), reason: 'a malformed name must not drop the position');
    expect((bad! as LocUpdate).name, isNull);
    expect((validPeerUpdate(loc())! as LocUpdate).name, isNull);
  });

  test('sends the name only when there is one', () {
    const base = LocUpdate(seed: 's', lat: 1, lng: 2, acc: null, hdg: null, spd: null, at: 3);
    expect(base.toJson().containsKey('name'), isFalse);
    const named = LocUpdate(seed: 's', lat: 1, lng: 2, acc: null, hdg: null, spd: null, at: 3, name: 'Anna');
    expect(named.toJson()['name'], 'Anna');
  });

  test('accepts a stop update', () {
    expect(validPeerUpdate({'k': 'stop', 'seed': 'abc'}), isA<StopUpdate>());
  });

  test('rejects out-of-range coordinates', () {
    expect(validPeerUpdate(loc(lat: 90.1)), isNull);
    expect(validPeerUpdate(loc(lat: -90.1)), isNull);
    expect(validPeerUpdate(loc(lng: 180.1)), isNull);
    expect(validPeerUpdate(loc(lng: -180.1)), isNull);
  });

  test('accepts the exact range bounds', () {
    expect(validPeerUpdate(loc(lat: 90, lng: 180)), isA<LocUpdate>());
    expect(validPeerUpdate(loc(lat: -90, lng: -180)), isA<LocUpdate>());
  });

  test('rejects non-finite numbers', () {
    expect(validPeerUpdate(loc(lat: double.nan)), isNull);
    expect(validPeerUpdate(loc(lng: double.infinity)), isNull);
    expect(validPeerUpdate(loc(acc: double.nan)), isNull);
    expect(validPeerUpdate(loc(at: double.infinity)), isNull);
  });

  test('rejects a bad seed', () {
    expect(validPeerUpdate(loc(seed: '')), isNull, reason: 'empty');
    expect(validPeerUpdate(loc(seed: 'a' * 129)), isNull, reason: 'over 128 chars');
    expect(validPeerUpdate(loc(seed: 42)), isNull, reason: 'not a string');
    expect(validPeerUpdate(loc(seed: null)), isNull, reason: 'missing');
  });

  test('accepts a seed at the 128-char limit', () {
    expect(validPeerUpdate(loc(seed: 'a' * 128)), isA<LocUpdate>());
  });

  test('rejects unknown or missing kinds', () {
    expect(validPeerUpdate({'k': 'evil', 'seed': 'abc'}), isNull);
    expect(validPeerUpdate({'seed': 'abc'}), isNull);
  });

  test('rejects non-map payloads', () {
    for (final junk in [null, 42, 'string', <int>[1, 2, 3], true]) {
      expect(validPeerUpdate(junk), isNull, reason: '$junk');
    }
  });

  test('parses every server frame and ignores anything unknown', () {
    expect(ServerMessage.parse({'t': 'hello', 'selfId': 'x'}), isA<HelloMessage>());
    expect(ServerMessage.parse({'t': 'peer', 'id': 'x', 'data': 'y'}), isA<PeerMessage>());
    expect(ServerMessage.parse({'t': 'request'}), isA<RequestMessage>());
    expect(ServerMessage.parse({'t': 'left', 'id': 'x'}), isA<LeftMessage>());
    expect(ServerMessage.parse({'t': 'presence', 'n': 3}), isA<PresenceMessage>());
    expect(ServerMessage.parse({'t': 'pong'}), isA<PongMessage>());
    expect(ServerMessage.parse({'t': 'error', 'reason': 'invalid-room'}), isA<ErrorMessage>());
    expect(ServerMessage.parse({'t': 'nonsense'}), isNull);
    expect(ServerMessage.parse({'t': 'peer', 'id': 'x'}), isNull, reason: 'missing data');
    expect(ServerMessage.parse('not a map'), isNull);
  });
}
