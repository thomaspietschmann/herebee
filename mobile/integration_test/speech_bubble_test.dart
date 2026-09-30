import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:herebee_location/herebee_location.dart';
import 'package:herebee/core/storage.dart';
import 'package:herebee/main.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

const String _secret = String.fromEnvironment('HEREBEE_SECRET');
const String _peerName = String.fromEnvironment('HEREBEE_PEER_NAME', defaultValue: 'Anna');
const String _peerMessage = String.fromEnvironment('HEREBEE_PEER_MESSAGE');
const String _ownMessage = String.fromEnvironment('HEREBEE_OWN_MESSAGE', defaultValue: 'Hallo aus der App');
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
    final center = tester.getCenter(finder.first);
    return center.dy >= 0 && center.dy <= size.height && center.dx >= 0 && center.dx <= size.width;
  });
  expect(ready, isTrue, reason: 'widget never became tappable on screen');
  await tester.tap(finder.first);
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('speech bubbles: a peer speaks, the toggle hides it, we speak back', (tester) async {
    expect(_secret, isNotEmpty);
    expect(_peerMessage, isNotEmpty);

    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(HereBeeApp(storage: await Storage.open()));

    final enter = find.text('Enter room');
    expect(await pumpUntil(tester, () => enter.evaluate().isNotEmpty), isTrue);
    await tapWhenOnScreen(tester, enter);
    expect(await pumpUntil(tester, () => enter.evaluate().isEmpty), isTrue);

    expect(await pumpUntil(tester, () => find.text(_peerName).evaluate().isNotEmpty), isTrue,
        reason: 'the peer bee should appear with its shared name');
    expect(await pumpUntil(tester, () => find.text(_peerMessage).evaluate().isNotEmpty), isTrue,
        reason: 'the peer message should show as a speech bubble');

    await tapWhenOnScreen(tester, find.bySemanticsLabel('Hide speech bubbles'));
    expect(await pumpUntil(tester, () => find.text(_peerMessage).evaluate().isEmpty), isTrue,
        reason: 'hiding bubbles removes them from the map');
    await tapWhenOnScreen(tester, find.bySemanticsLabel('Show speech bubbles'));
    expect(await pumpUntil(tester, () => find.text(_peerMessage).evaluate().isNotEmpty), isTrue);

    await tapWhenOnScreen(tester, find.text('i'));
    final title = find.text('How private is this?');
    expect(await pumpUntil(tester, () => title.evaluate().isNotEmpty), isTrue);
    await tester.pump(const Duration(seconds: 1));
    final topInset = MediaQueryData.fromView(tester.view).padding.top;
    expect(tester.getTopLeft(title).dy, greaterThan(topInset),
        reason: 'the info sheet must stay below the status bar');
    await tapWhenOnScreen(tester, find.byTooltip('Close'));
    await tester.pump(const Duration(seconds: 1));

    if (await HereBeeLocation.checkPermission() != LocationPermissionState.whileInUse) {
      markTestSkipped('location not pre-granted; own message not exercised');
      return;
    }
    await tapWhenOnScreen(tester, find.text('Share location'));
    expect(await pumpUntil(tester, () => find.textContaining('(you)').evaluate().isNotEmpty), isTrue);
    await pumpUntil(tester, () => find.byType(SnackBar).evaluate().isNotEmpty, timeout: const Duration(seconds: 3));
    tester.state<ScaffoldMessengerState>(find.byType(ScaffoldMessenger).first).removeCurrentSnackBar();
    await pumpUntil(tester, () => find.byType(SnackBar).evaluate().isEmpty, timeout: const Duration(seconds: 3));
    await tapWhenOnScreen(tester, find.textContaining('(you)'));
    await pumpUntil(tester, () => false, timeout: const Duration(milliseconds: 1500));
    await tapWhenOnScreen(tester, find.bySemanticsLabel('Say something'));
    final input = find.byKey(const ValueKey('say-input'));
    expect(await pumpUntil(tester, () => input.evaluate().isNotEmpty), isTrue);
    await tester.enterText(input, 'alter Text');
    await tapWhenOnScreen(tester, find.byTooltip('Clear'));
    expect(await pumpUntil(tester, () => tester.widget<TextField>(input).controller!.text.isEmpty), isTrue,
        reason: 'the clear button empties the field');
    await tester.enterText(input, _ownMessage);
    await tapWhenOnScreen(tester, find.text('Say'));
    expect(await pumpUntil(tester, () => find.text(_ownMessage).evaluate().isNotEmpty), isTrue,
        reason: 'our own bee shows what we said');

    await pumpUntil(tester, () => false, timeout: Duration(seconds: _holdSeconds));
  });
}
