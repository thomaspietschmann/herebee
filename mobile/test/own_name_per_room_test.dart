import 'package:flutter_test/flutter_test.dart';
import 'package:herebee/core/recent_rooms.dart';
import 'package:herebee/core/storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('our own name and its sharing choice stay in the room they were set in', () async {
    SharedPreferences.setMockInitialValues({});
    final storage = await Storage.open(device: MemorySecretStore());
    await storage.setOwnName('roomA', 'Tom');
    await storage.setSharesName('roomA', true);

    expect(storage.ownName('roomA'), 'Tom');
    expect(storage.sharesName('roomA'), isTrue);
    expect(storage.ownName('roomB'), isNull);
    expect(storage.sharesName('roomB'), isFalse);
  });

  test('names given to others stay in the room they were given in', () async {
    SharedPreferences.setMockInitialValues({});
    final storage = await Storage.open(device: MemorySecretStore());
    await storage.setCustomName('roomA', 'peer', 'Anna');

    expect(storage.customName('roomA', 'peer'), 'Anna');
    expect(storage.customName('roomB', 'peer'), isNull);
  });

  test('our bee is a different one in every room, and stable within one', () async {
    SharedPreferences.setMockInitialValues({});
    final device = MemorySecretStore();
    final storage = await Storage.open(device: device);
    final a = await storage.roomSeed('roomA');
    final b = await storage.roomSeed('roomB');

    expect(a, isNot(b));
    expect(await storage.roomSeed('roomA'), a);
    final reopened = await Storage.open(device: device);
    expect(await reopened.roomSeed('roomA'), a);
  });

  test('cross-room data of older builds is dropped', () async {
    SharedPreferences.setMockInitialValues({
      'herebee.seed': 'globalseed',
      'herebee.name.me': 'Tom',
      'herebee.name.other': 'Anna',
      'herebee.shareName': true,
      'herebee.name.roomA.other': 'Anna',
    });
    final storage = await Storage.open(device: MemorySecretStore());
    final prefs = await SharedPreferences.getInstance();

    expect(prefs.getString('herebee.seed'), isNull);
    expect(prefs.getString('herebee.name.me'), isNull);
    expect(prefs.getString('herebee.name.other'), isNull);
    expect(prefs.getBool('herebee.shareName'), isNull);
    expect(storage.customName('roomA', 'other'), 'Anna');
  });
}
