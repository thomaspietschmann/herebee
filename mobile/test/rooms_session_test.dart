import 'package:flutter_test/flutter_test.dart';
import 'package:herebee/core/crypto.dart';
import 'package:herebee/core/net.dart';
import 'package:herebee/core/storage.dart';
import 'package:herebee/core/types.dart';
import 'package:herebee/features/room/room_controller.dart';
import 'package:herebee/features/room/rooms_session.dart';
import 'package:shared_preferences/shared_preferences.dart';

class QuietNetClient extends NetClient {
  QuietNetClient({required super.keys, required super.handlers})
      : super(endpoint: 'ws://test', cid: 'cid', clientLabel: 'test/1');

  bool closed = false;

  @override
  Future<void> connect() async {}

  @override
  Future<void> broadcast(PeerUpdate update) async {}

  @override
  void resync() {}

  @override
  Future<void> close() async => closed = true;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Storage storage;
  late Map<String, QuietNetClient> nets;

  RoomRef ref() => (secret: generateSecret(), origin: 'https://herebee.app');

  RoomsSession session({int maxRooms = 5}) => RoomsSession(
        (room) => RoomController(
          secret: room.secret,
          storage: storage,
          languageCode: 'en',
          youSuffix: '(you)',
          origin: room.origin,
          netClientFactory: ({
            required String endpoint,
            required RoomKeys keys,
            required String cid,
            required String clientLabel,
            required NetHandlers handlers,
          }) {
            final net = QuietNetClient(keys: keys, handlers: handlers);
            nets[room.secret] = net;
            return net;
          },
        ),
        maxRooms: maxRooms,
      );

  Future<RoomController> enter(RoomsSession s, RoomRef room) async {
    final c = s.open(room);
    while (!c.ready) {
      await Future<void>.delayed(Duration.zero);
    }
    await c.enter();
    return c;
  }

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    storage = await Storage.open();
    nets = {};
  });

  test('switching keeps the other room connected', () async {
    final s = session();
    final a = ref(), b = ref();
    final ca = await enter(s, a);
    final cb = await enter(s, b);
    expect(s.active, b);

    expect(identical(s.open(a), ca), isTrue, reason: 'switching back reuses the room');
    expect(s.active, a);
    expect(nets[a.secret]!.closed, isFalse);
    expect(nets[b.secret]!.closed, isFalse);
    expect(s.joined, [a, b]);
    expect(cb.entered, isTrue);
    s.dispose();
  });

  test('leaving the active room falls back to the one used last', () async {
    final s = session();
    final a = ref(), b = ref(), c = ref();
    await enter(s, a);
    await enter(s, b);
    await enter(s, c);
    s.open(a);

    s.leave(a);
    expect(nets[a.secret]!.closed, isTrue);
    expect(s.active, c);
    expect(s.joined, [b, c]);

    s.leave(b);
    expect(s.active, c, reason: 'leaving a background room keeps the current one');
    s.leave(c);
    expect(s.active, isNull);
    expect(s.isEmpty, isTrue);
    s.dispose();
  });

  test('the number of rooms is capped', () async {
    final s = session(maxRooms: 2);
    final a = ref();
    s.open(a);
    s.open(ref());
    expect(s.full, isTrue);
    expect(() => s.open(ref()), throwsStateError);
    expect(() => s.open(a), returnsNormally, reason: 'an already joined room can still be switched to');
    s.dispose();
  });

  test('a message in a background room is counted and reported', () async {
    final s = session();
    final a = ref(), b = ref();
    final ca = await enter(s, a);
    await enter(s, b);
    final events = <RoomMessage>[];
    final sub = s.messagesElsewhere.listen(events.add);

    final seed = 'peerseed1';
    final now = DateTime.now().millisecondsSinceEpoch;
    ca.peers.upsert(LocUpdate(seed: seed, lat: 1, lng: 1, acc: null, hdg: null, spd: null, at: now));
    expect(ca.peers[seed], isNotNull);
    final net = nets[a.secret]!;
    net.handlers.onPeer('x', LocUpdate(seed: seed, lat: 1, lng: 1, acc: null, hdg: null, spd: null, at: now + 1, msg: 'hi', msgAt: now + 1));
    await Future<void>.delayed(Duration.zero);

    expect(events.map((e) => e.room), [a]);
    expect(s.unread(a), 1);
    expect(s.unreadElsewhere, 1);

    s.open(a);
    expect(s.unread(a), 0, reason: 'opening the room reads it');
    await sub.cancel();
    s.dispose();
  });
}
