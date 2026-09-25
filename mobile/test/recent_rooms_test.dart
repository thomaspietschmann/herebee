import 'package:flutter_test/flutter_test.dart';
import 'package:herebee/core/recent_rooms.dart';

void main() {
  late MemorySecretStore store;
  late DateTime now;
  late RecentRooms rooms;

  setUp(() {
    store = MemorySecretStore();
    now = DateTime(2026, 9, 25, 12);
    rooms = RecentRooms(store, clock: () => now);
  });

  test('starts empty and stays empty without an entered room', () async {
    await rooms.load();
    expect(rooms.rooms, isEmpty);
    expect(rooms.latest, isNull);
    expect(store.value, isNull);
  });

  test('entering a room puts it first; re-entering moves it back to the front', () async {
    await rooms.load();
    await rooms.touch('a');
    now = now.add(const Duration(minutes: 1));
    await rooms.touch('b');
    expect(rooms.rooms.map((r) => r.secret), ['b', 'a']);

    now = now.add(const Duration(minutes: 1));
    await rooms.touch('a');
    expect(rooms.rooms.map((r) => r.secret), ['a', 'b']);
    expect(rooms.latest!.secret, 'a');
    expect(rooms.latest!.lastEntered, now);
  });

  test('keeps at most five rooms', () async {
    await rooms.load();
    for (var i = 0; i < 7; i++) {
      now = now.add(const Duration(seconds: 1));
      await rooms.touch('r$i');
    }
    expect(rooms.rooms.map((r) => r.secret), ['r6', 'r5', 'r4', 'r3', 'r2']);
  });

  test('rooms expire three days after they were last entered', () async {
    await rooms.load();
    await rooms.touch('old');
    now = now.add(const Duration(days: 1));
    await rooms.touch('fresh');

    now = now.add(const Duration(days: 2, seconds: 1)); // old is now 3d+1s
    expect(rooms.rooms.map((r) => r.secret), ['fresh']);
    expect(rooms.latest!.secret, 'fresh');

    now = now.add(const Duration(days: 1));
    expect(rooms.rooms, isEmpty);
  });

  test('forget removes one room, forgetAll clears the store', () async {
    await rooms.load();
    await rooms.touch('a');
    await rooms.touch('b');
    await rooms.forget('a');
    expect(rooms.rooms.map((r) => r.secret), ['b']);
    await rooms.forgetAll();
    expect(rooms.rooms, isEmpty);
    expect(store.value, isNull, reason: 'an empty list must not leave a keychain item behind');
  });

  test('remembers peers met, newest first, without duplicates, capped', () async {
    await rooms.load();
    await rooms.touch('a');
    await rooms.sawPeers('a', ['p1', 'p2']);
    await rooms.sawPeers('a', ['p2', 'p3']);
    expect(rooms.byId('a')!.seeds, ['p3', 'p1', 'p2']);

    await rooms.sawPeers('a', ['p4', 'p5', 'p6']);
    expect(rooms.byId('a')!.seeds.length, RecentRooms.maxSeeds);
    expect(rooms.byId('a')!.seeds.first, 'p4');

    // Peers seen survive re-entering the room.
    await rooms.touch('a');
    expect(rooms.byId('a')!.seeds.length, RecentRooms.maxSeeds);

    // Unknown room: nothing is recorded, nothing is written.
    final before = store.value;
    await rooms.sawPeers('nope', ['x']);
    expect(store.value, before);
  });

  test('sawPeers does not rewrite the store when nothing is new', () async {
    await rooms.load();
    await rooms.touch('a');
    await rooms.sawPeers('a', ['p1']);
    var writes = 0;
    rooms.addListener(() => writes++);
    await rooms.sawPeers('a', ['p1']);
    await rooms.sawPeers('a', const []);
    expect(writes, 0);
  });

  test('round-trips through the store and drops what it cannot read', () async {
    await rooms.load();
    await rooms.touch('a');
    await rooms.sawPeers('a', ['p1']);

    final reloaded = RecentRooms(store, clock: () => now);
    await reloaded.load();
    expect(reloaded.rooms.single.secret, 'a');
    expect(reloaded.rooms.single.seeds, ['p1']);
    expect(reloaded.rooms.single.lastEntered, now);

    store.value = 'not json';
    final broken = RecentRooms(store, clock: () => now);
    await broken.load();
    expect(broken.rooms, isEmpty);

    store.value = '{"v":99,"rooms":[{"s":"a","t":1}]}';
    final future = RecentRooms(store, clock: () => now);
    await future.load();
    expect(future.rooms, isEmpty, reason: 'an unknown format version is ignored, not guessed at');
  });
}
