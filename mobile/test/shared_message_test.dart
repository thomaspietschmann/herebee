import 'package:flutter_test/flutter_test.dart';
import 'package:herebee/core/peer_state.dart';
import 'package:herebee/core/protocol.dart';
import 'package:herebee/core/types.dart';

const int t0 = 1700000000000;

LocUpdate fix({required int at, String? msg, int? msgAt}) =>
    LocUpdate(seed: 'p', lat: 1, lng: 2, acc: null, hdg: null, spd: null, at: at, msg: msg, msgAt: msgAt);

void main() {
  final now = DateTime.fromMillisecondsSinceEpoch(t0 + 60000);

  test('a new message is announced once, repeats are not', () {
    final peers = PeerStore();
    expect(peers.upsert(fix(at: t0, msg: 'hi', msgAt: t0), now: now), isTrue);
    expect(peers.upsert(fix(at: t0 + 1000, msg: 'hi', msgAt: t0), now: now), isFalse);
    expect(peers['p']!.message, 'hi');
    expect(peers.upsert(fix(at: t0 + 2000, msg: 'hi', msgAt: t0 + 1500), now: now), isTrue,
        reason: 'the same text said again is a new message');
  });

  test('an update without a message clears it', () {
    final peers = PeerStore()..upsert(fix(at: t0, msg: 'hi', msgAt: t0), now: now);
    peers.upsert(fix(at: t0 + 1000), now: now);
    expect(peers['p']!.message, isNull);
  });

  test('a stale replay cannot bring back an older message', () {
    final peers = PeerStore()..upsert(fix(at: t0 + 5000, msg: 'new', msgAt: t0 + 4000), now: now);
    peers.upsert(fix(at: t0 + 6000, msg: 'old', msgAt: t0), now: now);
    expect(peers['p']!.message, 'new');
  });

  test('age comes from the sender clock, so skew cannot keep a message alive', () {
    final skewed = DateTime.fromMillisecondsSinceEpoch(t0 - 3600000);
    final peers = PeerStore()..upsert(fix(at: t0, msg: 'hi', msgAt: t0 - 60000), now: skewed);
    expect(peers['p']!.messageAgeAt(skewed), const Duration(minutes: 1));
    peers.tick(skewed.add(const Duration(minutes: 9, seconds: 1)));
    expect(peers['p']!.message, isNull, reason: 'ten minutes after it was said, counted locally');
  });

  test('a message older than its lifetime is dropped on arrival', () {
    final peers = PeerStore()..upsert(fix(at: t0 + 11 * 60000, msg: 'hi', msgAt: t0), now: now);
    expect(peers['p']!.message, isNull);
  });

  test('validation keeps the frame but drops a malformed message', () {
    Map<String, Object?> frame(Map<String, Object?> extra) =>
        {'k': 'loc', 'seed': 'p', 'lat': 1, 'lng': 2, 'acc': null, 'hdg': null, 'spd': null, 'at': t0, ...extra};
    final ok = validPeerUpdate(frame({'msg': '  hi\u202e ', 'msgAt': t0})) as LocUpdate;
    expect(ok.msg, 'hi');
    expect(ok.msgAt, t0);
    final noTime = validPeerUpdate(frame({'msg': 'hi'})) as LocUpdate;
    expect(noTime.msg, isNull);
    final badTime = validPeerUpdate(frame({'msg': 'hi', 'msgAt': 'soon'})) as LocUpdate;
    expect(badTime.msg, isNull);
    final notText = validPeerUpdate(frame({'msg': 42, 'msgAt': t0})) as LocUpdate;
    expect(notText.msg, isNull);
  });
}
