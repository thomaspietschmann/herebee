/// The synthwave map style restyles the app chrome. Picking it in the settings
/// sheet must persist the choice and switch the theme live, and the four-way
/// picker must fit a narrow phone.
library;

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:herebee/core/recent_rooms.dart';
import 'package:herebee/core/storage.dart';
import 'package:herebee/features/hud/hud.dart';
import 'package:herebee/features/room/room_controller.dart';
import 'package:herebee/features/sheets/sheets.dart';
import 'package:herebee/l10n/app_localizations.dart';
import 'package:herebee/main.dart';
import 'package:herebee/ui/tokens.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<RoomController> _controller() async {
  SharedPreferences.setMockInitialValues({});
  final controller = RoomController(
    secret: 'ByxRdpvA5QovVHmew-gNMld8ocbrEDVaf6TJ7hM4XYI',
    storage: await Storage.open(device: MemorySecretStore()),
    languageCode: 'de',
    youSuffix: '(du)',
  );
  await controller.init();
  return controller;
}

/// The app's theme wiring (see HereBeeApp) around the HUD, without the map,
/// which is a native view the test harness cannot build.
Widget _app(RoomController c, {Locale locale = const Locale('de')}) => ValueListenableBuilder<MapThemePref>(
      valueListenable: c.storage.mapThemeListenable,
      builder: (context, pref, _) => MaterialApp(
        locale: locale,
        localizationsDelegates: const [
          L.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: L.supportedLocales,
        theme: themeFor(pref),
        home: Scaffold(
          body: Builder(
            builder: (context) => Hud(
              controller: c,
              onFitAll: () {},
              onGoTo: (_) {},
              onShareLink: () {},
              onToggleShare: () {},
              onInfo: () => showInfoSheet(context, controller: c),
              onRooms: () {},
            ),
          ),
        ),
      ),
    );

/// Fill of the dock's primary button, found through its label.
Color? _primaryFill(WidgetTester tester, String label) => tester
    .widget<Material>(find.ancestor(of: find.text(label), matching: find.byType(Material)).first)
    .color;

void main() {
  testWidgets('picking synthwave persists it and restyles the chrome live', (tester) async {
    final c = await _controller();
    addTearDown(c.dispose);
    await tester.pumpWidget(_app(c));
    await tester.pump();

    expect(_primaryFill(tester, 'Standort teilen'), HereBeeTokens.standard.signal);

    await tester.tap(find.byKey(const ValueKey('settings')));
    await tester.pumpAndSettle();
    for (final pref in MapThemePref.values) {
      expect(find.byKey(ValueKey('map-theme-${pref.name}')), findsOneWidget, reason: pref.name);
    }
    expect(find.text('Synthwave'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('map-theme-synthwave')));
    await tester.pumpAndSettle();
    expect(c.storage.mapTheme, MapThemePref.synthwave);
    expect((await SharedPreferences.getInstance()).getString('herebee.mapTheme'), 'synthwave');

    Navigator.of(tester.element(find.byKey(const ValueKey('map-theme-synthwave')))).pop();
    await tester.pumpAndSettle();
    // Dock labels go uppercase and the primary turns hot pink.
    expect(find.text('STANDORT TEILEN'), findsOneWidget);
    expect(_primaryFill(tester, 'STANDORT TEILEN'), HereBeeTokens.synthwave.signal);

    // And back: every other choice restores the standard look.
    await tester.tap(find.byKey(const ValueKey('settings')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('map-theme-dark')));
    await tester.pumpAndSettle();
    Navigator.of(tester.element(find.byKey(const ValueKey('map-theme-dark')))).pop();
    await tester.pumpAndSettle();
    expect(_primaryFill(tester, 'Standort teilen'), HereBeeTokens.standard.signal);
  });

  testWidgets('the four map styles fit a 320 px wide phone in every language', (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final c = await _controller();
    addTearDown(c.dispose);
    for (final theme in [MapThemePref.auto, MapThemePref.synthwave]) {
      await c.storage.setMapTheme(theme);
      for (final locale in L.supportedLocales) {
        await tester.pumpWidget(_app(c, locale: locale));
        await tester.pump();
        await tester.tap(find.byKey(const ValueKey('settings')));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull, reason: '${theme.name} ${locale.languageCode}');
        for (final pref in MapThemePref.values) {
          final box = tester.getRect(find.byKey(ValueKey('map-theme-${pref.name}')));
          expect(box.left, greaterThanOrEqualTo(0), reason: pref.name);
          expect(box.right, lessThanOrEqualTo(320), reason: pref.name);
        }
        Navigator.of(tester.element(find.byKey(const ValueKey('map-theme-auto')))).pop();
        await tester.pumpAndSettle();
      }
    }
  });
}
