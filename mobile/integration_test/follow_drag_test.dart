import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:herebee/core/storage.dart';
import 'package:herebee/features/map/bee_marker.dart';
import 'package:herebee/features/map/follow_drag.dart';
import 'package:herebee/main.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

const String _secret = String.fromEnvironment('HEREBEE_SECRET');
const int _holdSeconds = int.fromEnvironment('HEREBEE_HOLD_SECONDS');
const int _backgroundSeconds = int.fromEnvironment('HEREBEE_BACKGROUND_SECONDS');

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

Future<void> hold(WidgetTester tester, String tag) async {
  if (_holdSeconds == 0) return;
  debugPrint('HOLD:$tag');
  for (var i = 0; i < _holdSeconds * 10; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('following resists a short drag and pops the pin on a long one', (tester) async {
    expect(_secret, isNotEmpty);
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(HereBeeApp(storage: await Storage.open()));

    final enter = find.text('Enter room');
    expect(await pumpUntil(tester, () => enter.evaluate().isNotEmpty), isTrue);
    await tester.ensureVisible(enter.first);
    await tester.pumpAndSettle();
    await tester.tap(enter.first);
    expect(await pumpUntil(tester, () => find.byType(BeeMarker).evaluate().isNotEmpty), isTrue);
    await tester.pump(const Duration(seconds: 2));

    await tester.tap(find.descendant(of: find.byType(BeeMarker).first, matching: find.byType(SvgPicture)));
    final follow = find.bySemanticsLabel('Follow');
    expect(await pumpUntil(tester, () => follow.evaluate().isNotEmpty), isTrue);
    await tester.pump(const Duration(milliseconds: 500));
    await tester.tap(follow.first);
    expect(await pumpUntil(tester, () => find.byType(FollowPin).evaluate().isNotEmpty), isTrue,
        reason: 'the pin shows above the followed bee');
    await tester.tapAt(const Offset(60, 420));
    await tester.pump(const Duration(seconds: 2));
    await hold(tester, 'pinned');

    if (_backgroundSeconds > 0) {
      debugPrint('HOLD:background');
      final until = DateTime.now().add(const Duration(seconds: _backgroundSeconds));
      while (DateTime.now().isBefore(until)) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      await tester.pump(const Duration(seconds: 3));
      expect(find.byType(FollowPin), findsOneWidget, reason: 'following survives a trip to the background');
    }

    final size = tester.view.physicalSize / tester.view.devicePixelRatio;
    final from = Offset(size.width / 2, size.height * 0.62);

    final disc = find.descendant(of: find.byType(BeeMarker).first, matching: find.byType(SvgPicture));
    final before = tester.getCenter(disc);
    final short = await tester.startGesture(from);
    for (var i = 1; i <= 8; i++) {
      await short.moveTo(from + Offset(0, 5.0 * i));
      await tester.pump(const Duration(milliseconds: 16));
    }
    await tester.pump(const Duration(milliseconds: 100));
    final shifted = (tester.getCenter(disc) - before).distance;
    expect(shifted, inInclusiveRange(4, 24), reason: 'the map trails the finger only a little');
    await hold(tester, 'stretched');
    expect(find.byType(FollowPin), findsOneWidget);
    await short.up();
    await tester.pump(const Duration(seconds: 1));
    expect(find.byType(FollowPin), findsOneWidget, reason: 'a short drag keeps following');

    final long = await tester.startGesture(from);
    var burstSeen = false;
    for (var i = 1; i <= 45; i++) {
      await long.moveTo(from + Offset(0, 6.0 * i));
      await tester.pump(const Duration(milliseconds: 16));
      if (i == 28) {
        await tester.pump(const Duration(milliseconds: 90));
        await hold(tester, 'burst');
      }
      burstSeen |= tester.widgetList<FollowPin>(find.byType(FollowPin)).any((p) => p.bursting);
    }
    await long.up();
    expect(burstSeen, isTrue, reason: 'the pin bursts once the drag goes past the threshold');
    expect(await pumpUntil(tester, () => find.byType(FollowPin).evaluate().isEmpty), isTrue,
        reason: 'following ends after the burst');
    await tester.pump(const Duration(seconds: 2));
    await hold(tester, 'free');
  });
}
