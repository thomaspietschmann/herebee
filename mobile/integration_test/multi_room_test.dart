import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:herebee/app_config.dart';
import 'package:herebee/core/names.dart';
import 'package:herebee/core/storage.dart';
import 'package:herebee/main.dart';
import 'package:herebee_location/herebee_location.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

const String _secret = String.fromEnvironment('HEREBEE_SECRET');
const String _secretB = String.fromEnvironment('HEREBEE_SECRET_B');
const String _seedA = String.fromEnvironment('HEREBEE_PEER_SEED', defaultValue: 'dev-anna');
const String _seedB = String.fromEnvironment('HEREBEE_PEER_SEED_B', defaultValue: 'dev-ben');

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
  await pumpUntil(tester, () => finder.evaluate().isNotEmpty);
  if (finder.evaluate().isNotEmpty) {
    await tester.ensureVisible(finder.first);
    await tester.pump(const Duration(milliseconds: 300));
  }
  final ready = await pumpUntil(tester, () {
    if (finder.evaluate().isEmpty) return false;
    final c = tester.getCenter(finder.first);
    return c.dy >= 0 && c.dy <= size.height && c.dx >= 0 && c.dx <= size.width;
  });
  expect(ready, isTrue,
      reason: 'widget never became tappable on screen: $finder at '
          '${finder.evaluate().isEmpty ? '-' : tester.getCenter(finder.first)} in $size, '
          'insets ${MediaQueryData.fromView(tester.view).viewInsets}');
  await tester.tap(finder.first);
}

Future<void> settleSheet(WidgetTester tester) => pumpUntil(tester, () => false, timeout: const Duration(milliseconds: 700));

Future<void> dropSnackBars(WidgetTester tester) async {
  await pumpUntil(tester, () => find.byType(SnackBar).evaluate().isNotEmpty, timeout: const Duration(seconds: 3));
  for (final state in tester.stateList<ScaffoldMessengerState>(find.byType(ScaffoldMessenger))) {
    state.removeCurrentSnackBar();
  }
  await pumpUntil(tester, () => find.byType(SnackBar).evaluate().isEmpty, timeout: const Duration(seconds: 3));
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('two rooms at once: switch, share in both, leave one', (tester) async {
    expect(_secret, isNotEmpty);
    expect(_secretB, isNotEmpty);
    final anna = nameFromSeed(_seedA, 'en');
    final ben = nameFromSeed(_seedB, 'en');

    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(HereBeeApp(storage: await Storage.open()));

    final enter = find.text('Enter room');
    expect(await pumpUntil(tester, () => enter.evaluate().isNotEmpty), isTrue);
    await tapWhenOnScreen(tester, enter);
    expect(await pumpUntil(tester, () => enter.evaluate().isEmpty), isTrue);
    expect(await pumpUntil(tester, () => find.text(anna).evaluate().isNotEmpty), isTrue,
        reason: 'room A shows its peer');
    expect(find.text('2 here'), findsOneWidget, reason: 'the roster shows once there is company');

    await settleSheet(tester);
    await tapWhenOnScreen(tester, find.byKey(const ValueKey('rooms-chip')));
    final link = find.byType(TextField);
    expect(await pumpUntil(tester, () => link.evaluate().isNotEmpty), isTrue);
    await tester.enterText(link, AppConfig.roomLink(AppConfig.defaultOrigin, _secretB));
    expect(await pumpUntil(tester, () => find.text(ben).evaluate().isNotEmpty), isTrue,
        reason: 'room B opens without the welcome sheet and shows its own peer');
    expect(enter, findsNothing, reason: 'the welcome sheet is only for the first room');
    expect(find.text(anna), findsNothing, reason: 'room A stays in room A');
    expect(find.byKey(const ValueKey('rooms-count')), findsOneWidget);

    await settleSheet(tester);
    await tapWhenOnScreen(tester, find.byKey(const ValueKey('rooms-chip')));
    expect(await pumpUntil(tester, () => find.text('Joined').evaluate().isNotEmpty), isTrue);
    await tapWhenOnScreen(tester, find.widgetWithText(ListTile, anna));
    expect(await pumpUntil(tester, () => find.text(anna).evaluate().isNotEmpty), isTrue,
        reason: 'back in room A, its peer is still live');
    await settleSheet(tester);
    expect(enter, findsNothing, reason: 'a joined room does not ask again');

    if (await HereBeeLocation.checkPermission() != LocationPermissionState.whileInUse) {
      markTestSkipped('location not pre-granted; sharing across rooms not exercised');
      return;
    }

    await tapWhenOnScreen(tester, find.text('Share location'));
    expect(await pumpUntil(tester, () => find.text('Stop sharing').evaluate().isNotEmpty), isTrue);
    expect(await pumpUntil(tester, () => find.textContaining('(you)').evaluate().isNotEmpty), isTrue);
    await dropSnackBars(tester);

    await tapWhenOnScreen(tester, find.byKey(const ValueKey('rooms-chip')));
    expect(await pumpUntil(tester, () => find.widgetWithText(ListTile, ben).evaluate().isNotEmpty), isTrue);
    await tapWhenOnScreen(tester, find.widgetWithText(ListTile, ben));
    expect(await pumpUntil(tester, () => find.text('Share location').evaluate().isNotEmpty), isTrue,
        reason: 'sharing is per room: B does not share yet');
    await settleSheet(tester);
    await tapWhenOnScreen(tester, find.text('Share location'));
    expect(await pumpUntil(tester, () => find.text('Stop sharing').evaluate().isNotEmpty), isTrue);
    await dropSnackBars(tester);

    await tapWhenOnScreen(tester, find.byKey(const ValueKey('rooms-chip')));
    expect(await pumpUntil(tester, () => find.textContaining('Sharing location').evaluate().length == 2), isTrue,
        reason: 'both joined rooms say they share');
    final leaveA = find.byKey(ValueKey('leave-$_secret'));
    await tapWhenOnScreen(tester, leaveA);
    await settleSheet(tester);
    expect(find.text('Stop sharing'), findsOneWidget, reason: 'B still shares after A was left');
    expect(await HereBeeLocation.isSharing(), isTrue, reason: 'leaving A must not stop the platform session');
    expect(find.byKey(const ValueKey('rooms-count')), findsNothing);

    await tapWhenOnScreen(tester, find.text('Stop sharing'));
    expect(await pumpUntil(tester, () => find.text('Share location').evaluate().isNotEmpty), isTrue);
    await pumpUntil(tester, () => false, timeout: const Duration(seconds: 1));
    expect(await HereBeeLocation.isSharing(), isFalse, reason: 'the last room to stop ends the session');
  });
}
