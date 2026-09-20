/// Phase 2 acceptance, driven on a real device or simulator.
///
/// The map is a native platform view, so this cannot run in the headless test
/// harness (see test/widget_test.dart). Run it against a booted simulator or a
/// connected phone, with a relay and a peer reachable at HEREBEE_ORIGIN:
///
///   npx tsx scripts/fake-peer.ts --ws ws://127.0.0.1:3100/ws --seed dev-anna
///   flutter test integration_test/room_flow_test.dart \
///     --dart-define=HEREBEE_ORIGIN=http://127.0.0.1:3100 \
///     --dart-define=HEREBEE_SECRET=`<the secret the peer printed>`
///
/// It walks the gate, waits for the peer's encrypted position to arrive, and
/// checks that a bee with the derived nickname is on the map. That exercises the
/// whole chain: style, tiles, socket, decryption, identity derivation, markers.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:herebee/core/names.dart';
import 'package:herebee/core/storage.dart';
import 'package:herebee/main.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

const String _secret = String.fromEnvironment('HEREBEE_SECRET');
const String _peerSeed = String.fromEnvironment('HEREBEE_PEER_SEED', defaultValue: 'dev-anna');

/// Keeps the app on screen after the assertions pass, so a screenshot can be
/// taken from outside (`xcrun simctl io booted screenshot`). Zero by default.
const int _holdSeconds = int.fromEnvironment('HEREBEE_HOLD_SECONDS');

/// Pump frames until [condition] holds or [timeout] elapses. Fixed-duration
/// pumps are flaky here: real I/O (HKDF, the socket, the first tile) has to make
/// progress, and how long that takes varies by machine.
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

/// Tap a widget once it is actually on screen.
///
/// A sheet slides up, so the moment its button EXISTS it is still below the
/// fold and a tap lands outside the view. Waiting for the widget to be within
/// the viewport is the difference between a test that passes and one that
/// silently taps nothing.
Future<void> tapWhenOnScreen(WidgetTester tester, Finder finder) async {
  final size = tester.view.physicalSize / tester.view.devicePixelRatio;
  final ready = await pumpUntil(tester, () {
    if (finder.evaluate().isEmpty) return false;
    final center = tester.getCenter(finder);
    return center.dy >= 0 && center.dy <= size.height && center.dx >= 0 && center.dx <= size.width;
  });
  expect(ready, isTrue, reason: 'widget never became tappable on screen');
  await tester.tap(finder);
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('enters a room and renders a peer that is sharing', (tester) async {
    expect(_secret, isNotEmpty,
        reason: 'pass --dart-define=HEREBEE_SECRET=<secret> from scripts/fake-peer.ts');

    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(HereBeeApp(storage: await Storage.open()));

    // The gate must be up, and up BEFORE anything has connected.
    final enter = find.text('Enter room');
    expect(await pumpUntil(tester, () => enter.evaluate().isNotEmpty), isTrue,
        reason: 'the entry gate must appear and block until the user decides');

    await tapWhenOnScreen(tester, enter);
    expect(await pumpUntil(tester, () => enter.evaluate().isEmpty), isTrue,
        reason: 'the gate should close once entered');

    // The peer broadcasts once a second. Its nickname is derived locally from
    // the seed, so seeing it proves the whole chain: socket, decryption,
    // validation, identity derivation and the marker layer.
    final expectedName = englishName(_peerSeed);
    final bee = find.textContaining(expectedName);
    expect(await pumpUntil(tester, () => bee.evaluate().isNotEmpty), isTrue,
        reason: 'expected a bee labelled "$expectedName" on the map');

    // Two people in the room now: the walking peer and us, watching.
    expect(await pumpUntil(tester, () => find.text('2 here').evaluate().isNotEmpty), isTrue,
        reason: 'the roster should count the peer and this watcher');

    // Fit-all with a single sharer zooms to it. Worth exercising here because a
    // wide initial view shows no tiles when the basemap is a small local
    // extract, which looks exactly like a rendering bug and is not one.
    await tapWhenOnScreen(tester, find.bySemanticsLabel('Fit everyone on screen'));
    await tester.pump(const Duration(seconds: 2));

    await pumpUntil(tester, () => false, timeout: Duration(seconds: _holdSeconds));
  });
}
