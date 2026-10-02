import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:herebee/core/storage.dart';
import 'package:herebee/main.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

const int _holdSeconds = int.fromEnvironment('HEREBEE_HOLD_SECONDS', defaultValue: 6);
const String _startTheme = String.fromEnvironment('HEREBEE_START_THEME');

Future<bool> pumpUntil(WidgetTester tester, bool Function() condition,
    {Duration timeout = const Duration(seconds: 25)}) async {
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

  testWidgets('the map style can be switched to dark, synthwave and back from the settings', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final storage = await Storage.open();
    if (_startTheme == 'dark') await storage.setMapTheme(MapThemePref.dark);
    if (_startTheme == 'synthwave') await storage.setMapTheme(MapThemePref.synthwave);
    await tester.pumpWidget(HereBeeApp(storage: storage));

    final enter = find.text('Enter room');
    expect(await pumpUntil(tester, () => enter.evaluate().isNotEmpty), isTrue);
    await tapWhenOnScreen(tester, enter);
    expect(await pumpUntil(tester, () => enter.evaluate().isEmpty), isTrue);
    await tapWhenOnScreen(tester, find.text('Share location'));
    await pumpUntil(tester, () => find.textContaining('(you)').evaluate().isNotEmpty);
    await pumpUntil(tester, () => find.byType(SnackBar).evaluate().isNotEmpty, timeout: const Duration(seconds: 3));
    tester.state<ScaffoldMessengerState>(find.byType(ScaffoldMessenger).first).removeCurrentSnackBar();
    debugPrint('THEME light');
    await pumpUntil(tester, () => false, timeout: Duration(seconds: _holdSeconds));

    await tapWhenOnScreen(tester, find.byKey(const ValueKey('settings')));
    await tapWhenOnScreen(tester, find.byKey(const ValueKey('map-theme-dark')));
    expect(storage.mapTheme, MapThemePref.dark);
    debugPrint('THEME sheet');
    await pumpUntil(tester, () => false, timeout: Duration(seconds: _holdSeconds));
    await tapWhenOnScreen(tester, find.byTooltip('Close'));
    debugPrint('THEME dark');
    await pumpUntil(tester, () => false, timeout: Duration(seconds: _holdSeconds));

    await tapWhenOnScreen(tester, find.byKey(const ValueKey('settings')));
    await tapWhenOnScreen(tester, find.byKey(const ValueKey('map-theme-synthwave')));
    expect(storage.mapTheme, MapThemePref.synthwave);
    await tapWhenOnScreen(tester, find.byTooltip('Close'));
    debugPrint('THEME synthwave');
    await pumpUntil(tester, () => false, timeout: Duration(seconds: _holdSeconds));

    await tapWhenOnScreen(tester, find.byKey(const ValueKey('settings')));
    await tapWhenOnScreen(tester, find.byKey(const ValueKey('map-theme-auto')));
    expect(storage.mapTheme, MapThemePref.auto);
    await tapWhenOnScreen(tester, find.byTooltip('Close'));
    debugPrint('THEME auto');
    await pumpUntil(tester, () => false, timeout: Duration(seconds: _holdSeconds));
  });
}
