import 'package:flutter_test/flutter_test.dart';
import 'package:herebee/core/storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('our own name and its sharing choice stay in the room they were set in', () async {
    SharedPreferences.setMockInitialValues({});
    final storage = await Storage.open();
    await storage.setOwnName('roomA', 'Tom');
    await storage.setSharesName('roomA', true);

    expect(storage.ownName('roomA'), 'Tom');
    expect(storage.sharesName('roomA'), isTrue);
    expect(storage.ownName('roomB'), isNull, reason: 'a new room starts without a name');
    expect(storage.sharesName('roomB'), isFalse, reason: 'and without sharing one');
  });

  test('the room-independent own name of older builds is dropped', () async {
    SharedPreferences.setMockInitialValues({
      'herebee.name.me': 'Tom',
      'herebee.name.other': 'Anna',
      'herebee.shareName': true,
    });
    final storage = await Storage.open();
    await storage.dropLegacyOwnName('me');

    expect(storage.customName('me'), isNull);
    expect(storage.customName('other'), 'Anna', reason: 'names for other people are kept');
    expect(storage.sharesName('anyRoom'), isFalse);
  });
}
