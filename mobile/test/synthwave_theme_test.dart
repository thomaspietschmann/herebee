/// The neon map styles restyle the app chrome. Picking one from the settings
/// sheet's dropdown must persist the choice and switch the theme live, and the
/// four-way picker and its dropdown must fit a narrow phone.
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
  testWidgets('picking a neon style from the dropdown persists it and restyles the chrome live', (tester) async {
    final c = await _controller();
    addTearDown(c.dispose);
    await tester.pumpWidget(_app(c));
    await tester.pump();

    expect(_primaryFill(tester, 'Standort teilen'), HereBeeTokens.standard.signal);

    await tester.tap(find.byKey(const ValueKey('settings')));
    await tester.pumpAndSettle();
    for (final key in ['auto', 'light', 'dark', 'neon']) {
      expect(find.byKey(ValueKey('map-theme-$key')), findsOneWidget, reason: key);
    }
    expect(find.text('Synthwave'), findsOneWidget);
    for (final pref in MapThemePref.neon) {
      expect(find.byKey(ValueKey('map-theme-${pref.name}')), findsNothing, reason: pref.name);
    }

    await tester.tap(find.byKey(const ValueKey('map-theme-neon')));
    await tester.pumpAndSettle();
    for (final pref in MapThemePref.neon) {
      expect(find.byKey(ValueKey('map-theme-${pref.name}')), findsOneWidget, reason: pref.name);
    }
    await tester.tap(find.byKey(const ValueKey('map-theme-tron')));
    await tester.pumpAndSettle();
    expect(c.storage.mapTheme, MapThemePref.tron);
    expect((await SharedPreferences.getInstance()).getString('herebee.mapTheme'), 'tron');
    expect(find.byKey(const ValueKey('map-theme-tron')), findsNothing);
    expect(find.text('Tron'), findsOneWidget);

    Navigator.of(tester.element(find.byKey(const ValueKey('map-theme-neon')))).pop();
    await tester.pumpAndSettle();
    expect(find.text('Standort teilen'), findsOneWidget);
    expect(_primaryFill(tester, 'Standort teilen'), HereBeeTokens.tron.signal);

    // And back: every other choice restores the standard look.
    await tester.tap(find.byKey(const ValueKey('settings')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('map-theme-dark')));
    await tester.pumpAndSettle();
    Navigator.of(tester.element(find.byKey(const ValueKey('map-theme-dark')))).pop();
    await tester.pumpAndSettle();
    expect(_primaryFill(tester, 'Standort teilen'), HereBeeTokens.standard.signal);
  });

  test('the chrome follows the map: lighter over the dark map, standard shapes and type everywhere', () {
    HereBeeTokens tokensOf(ThemeData theme) => theme.extension<HereBeeTokens>()!;
    expect(tokensOf(themeFor(MapThemePref.light)), HereBeeTokens.standard);
    expect(tokensOf(themeFor(MapThemePref.auto)), HereBeeTokens.standard);
    expect(tokensOf(themeFor(MapThemePref.auto, platform: Brightness.dark)), HereBeeTokens.dark);
    expect(tokensOf(themeFor(MapThemePref.dark)), HereBeeTokens.dark);
    expect(tokensOf(themeFor(MapThemePref.synthwave)), HereBeeTokens.synthwave);
    final neon = [
      HereBeeTokens.synthwave,
      HereBeeTokens.outrun,
      HereBeeTokens.miami,
      HereBeeTokens.tron,
      HereBeeTokens.vapor,
      HereBeeTokens.amber,
    ];
    expect([for (final p in MapThemePref.neon) tokensOf(themeFor(p))], neon);
    for (final t in [HereBeeTokens.dark, ...neon]) {
      expect(t.pillRadius, HereBeeTokens.standard.pillRadius);
      expect(t.panelRadius, HereBeeTokens.standard.panelRadius);
      expect(t.fontFamily, HereBeeTokens.standard.fontFamily);
      expect(t.uppercase, HereBeeTokens.standard.uppercase);
    }
  });

  testWidgets('the map style picker and its dropdown fit a 320 px wide phone in every language', (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final c = await _controller();
    addTearDown(c.dispose);
    for (final theme in [MapThemePref.auto, MapThemePref.synthwave, MapThemePref.amber]) {
      await c.storage.setMapTheme(theme);
      for (final locale in L.supportedLocales) {
        await tester.pumpWidget(_app(c, locale: locale));
        await tester.pump();
        await tester.tap(find.byKey(const ValueKey('settings')));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull, reason: '${theme.name} ${locale.languageCode}');
        await tester.tap(find.byKey(const ValueKey('map-theme-neon')));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull, reason: '${theme.name} ${locale.languageCode} open');
        for (final key in ['auto', 'light', 'dark', 'neon', ...MapThemePref.neon.map((p) => p.name)]) {
          final box = tester.getRect(find.byKey(ValueKey('map-theme-$key')));
          expect(box.left, greaterThanOrEqualTo(0), reason: key);
          expect(box.right, lessThanOrEqualTo(320), reason: key);
        }
        Navigator.of(tester.element(find.byKey(const ValueKey('map-theme-auto')))).pop();
        await tester.pumpAndSettle();
      }
    }
  });
}
