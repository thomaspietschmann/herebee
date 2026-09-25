/// Recent rooms on a real device or simulator, against the platform's secure
/// storage (Keychain / Keystore), which the headless harness cannot exercise.
///
///   flutter test integration_test/recent_rooms_test.dart \
///     --dart-define=HEREBEE_ORIGIN=http://127.0.0.1:3100
///
/// Walks: launch without a link, enter the minted room, check it is remembered
/// and that a fresh store reads it back from secure storage; open the rooms
/// sheet from the brand chip, start a new room, check the app switched and the
/// list now holds both; relaunch the widget tree and check it opens the newest.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:herebee/core/recent_rooms.dart';
import 'package:herebee/core/storage.dart';
import 'package:herebee/main.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

const int _holdSeconds = int.fromEnvironment('HEREBEE_HOLD_SECONDS');

Future<bool> pumpUntil(
  WidgetTester tester,
  bool Function() condition, {
  Duration timeout = const Duration(seconds: 25),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(deadline)) {
    if (condition()) return true;
    await tester.pump(const Duration(milliseconds: 200));
  }
  return condition();
}

Future<void> tapWhenOnScreen(WidgetTester tester, Finder finder) async {
  final size = tester.view.physicalSize / tester.view.devicePixelRatio;
  final ready = await pumpUntil(tester, () {
    if (finder.evaluate().isEmpty) return false;
    final c = tester.getCenter(finder);
    return c.dy >= 0 && c.dy <= size.height && c.dx >= 0 && c.dx <= size.width;
  });
  expect(ready, isTrue, reason: 'widget never became tappable on screen');
  await tester.tap(finder);
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('remembers entered rooms in secure storage and reopens the newest', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final storage = await Storage.open();
    final recent = RecentRooms(SecureSecretStore());
    await recent.load();
    await recent.forgetAll(); // a previous run must not leak into this one

    await tester.pumpWidget(HereBeeApp(storage: storage, recent: recent));
    final enter = find.text('Enter room');
    expect(await pumpUntil(tester, () => enter.evaluate().isNotEmpty), isTrue);
    expect(recent.rooms, isEmpty, reason: 'nothing is remembered before the user enters');

    await tapWhenOnScreen(tester, enter);
    expect(await pumpUntil(tester, () => recent.rooms.length == 1), isTrue,
        reason: 'entering the room must record it');
    final first = recent.latest!.secret;

    // Secure storage really holds it: a fresh store, no shared state, reads it back.
    final fresh = RecentRooms(SecureSecretStore());
    await fresh.load();
    expect(fresh.rooms.map((r) => r.secret), [first]);

    // Brand chip -> rooms sheet -> new room. Wait for the gate to be fully
    // gone first: while it animates away, its barrier still swallows taps.
    expect(await pumpUntil(tester, () => enter.evaluate().isEmpty), isTrue);
    await tester.pump(const Duration(milliseconds: 600));
    await tapWhenOnScreen(tester, find.byKey(const ValueKey('rooms-chip')));
    expect(
        await pumpUntil(tester, () => find.textContaining('You are here').evaluate().isNotEmpty),
        isTrue,
        reason: 'the sheet must list the current room');
    await tapWhenOnScreen(tester, find.text('Open a new room'));
    await tapWhenOnScreen(tester, find.text('Enter room'));
    expect(await pumpUntil(tester, () => recent.rooms.length == 2), isTrue);
    final second = recent.latest!.secret;
    expect(second, isNot(first));

    // Relaunch without a link: lands in the newest room (gate up).
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
    final again = RecentRooms(SecureSecretStore());
    await tester.pumpWidget(HereBeeApp(storage: storage, recent: again));
    expect(await pumpUntil(tester, () => find.text('Enter room').evaluate().isNotEmpty), isTrue);
    expect(again.latest!.secret, second);

    // Forget from the sheet.
    await tapWhenOnScreen(tester, find.text('Enter room'));
    expect(await pumpUntil(tester, () => find.text('Enter room').evaluate().isEmpty), isTrue);
    await tester.pump(const Duration(milliseconds: 600));
    await tapWhenOnScreen(tester, find.byKey(const ValueKey('rooms-chip')));
    expect(await pumpUntil(tester, () => find.text('Forget all').evaluate().isNotEmpty), isTrue);
    // Optional pause with the populated sheet on screen, for a screenshot.
    await pumpUntil(tester, () => false, timeout: Duration(seconds: _holdSeconds));
    await tester.tap(find.text('Forget all'));
    expect(await pumpUntil(tester, () => again.rooms.isEmpty), isTrue);
    final cleared = RecentRooms(SecureSecretStore());
    await cleared.load();
    expect(cleared.rooms, isEmpty, reason: 'forget-all must delete the secure item');
  });
}
