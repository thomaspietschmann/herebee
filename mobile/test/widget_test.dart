/// Widget-level checks for the parts that can render headlessly.
///
/// The map is a native platform view and cannot be built by the test harness, so
/// the room screen itself is verified on a device instead (see the Phase 2
/// acceptance run). Everything around it — localization, the HUD, the sheets and
/// the markup renderer — is covered here, which is where the string pipeline
/// from client/src/i18n.ts actually gets exercised.
library;

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:herebee/core/storage.dart';
import 'package:herebee/features/hud/hud.dart';
import 'package:herebee/features/room/room_controller.dart';
import 'package:herebee/features/sheets/sheets.dart';
import 'package:herebee/l10n/app_localizations.dart';
import 'package:herebee/util/markup.dart';
import 'package:shared_preferences/shared_preferences.dart';

Widget harness(Widget child, {Locale locale = const Locale('de')}) => MaterialApp(
      locale: locale,
      localizationsDelegates: const [
        L.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: L.supportedLocales,
      theme: ThemeData(brightness: Brightness.dark),
      home: Scaffold(body: child),
    );

Future<RoomController> makeController() async {
  SharedPreferences.setMockInitialValues({});
  final controller = RoomController(
    secret: 'ByxRdpvA5QovVHmew-gNMld8ocbrEDVaf6TJ7hM4XYI',
    storage: await Storage.open(),
    languageCode: 'de',
    youSuffix: '(du)',
  );
  await controller.init();
  return controller;
}

void main() {
  test('every supported locale resolves the full key set', () async {
    for (final locale in L.supportedLocales) {
      final l = await L.delegate.load(locale);
      expect(l.title, isNotEmpty, reason: '${locale.languageCode}: title');
      expect(l.hint, isNotEmpty, reason: '${locale.languageCode}: hint');
      expect(l.shareLocation, isNotEmpty, reason: '${locale.languageCode}: shareLocation');
      expect(l.here('3'), contains('3'), reason: '${locale.languageCode}: placeholder');
      expect(l.hereActiveOffline('2', '1'), allOf(contains('2'), contains('1')));
    }
    expect(L.supportedLocales.map((l) => l.languageCode).toSet(),
        {'de', 'en', 'es', 'it', 'fr', 'pt'});
  });

  testWidgets('the HUD shows the link state and the room link action', (tester) async {
    final controller = await makeController();
    addTearDown(controller.dispose);
    // The chip announces the link state to screen readers, so assert on the
    // semantics tree rather than on painted text.
    // Disposed at the end of the body, not via addTearDown: the framework's
    // end-of-test check runs before tear-downs do.
    final semantics = tester.ensureSemantics();

    await tester.pumpWidget(harness(Hud(
      controller: controller,
      onFitAll: () {},
      onGoTo: (_) {},
      onShareLink: () {},
      onToggleShare: () {},
      onInfo: () {},
    )));
    await tester.pump();

    expect(find.text('HereBee'), findsOneWidget, reason: 'wordmark, split into two spans');
    expect(find.text('Link teilen'), findsOneWidget);
    // Nothing has connected yet, so the chip must not claim otherwise.
    expect(find.bySemanticsLabel('Verbindung…'), findsOneWidget);
    semantics.dispose();
  });

  testWidgets('the entry gate explains presence before anything connects', (tester) async {
    await tester.pumpWidget(harness(Builder(
      builder: (context) => TextButton(
        onPressed: () => showWelcomeSheet(context),
        child: const Text('open'),
      ),
    )));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.text('Willkommen bei HereBee'), findsOneWidget);
    expect(find.text('Raum betreten'), findsOneWidget);
  });

  testWidgets('the legal sheet carries its unfilled placeholders visibly', (tester) async {
    await tester.pumpWidget(harness(Builder(
      builder: (context) => TextButton(
        onPressed: () => showLegalSheet(context),
        child: const Text('open'),
      ),
    )));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.text('Impressum'), findsOneWidget);
    // These must stay visible until someone fills them in before release.
    expect(find.textContaining('wird vor Veröffentlichung ergänzt'), findsWidgets);
  });

  testWidgets('the privacy sheet describes background location, not the old watcher build',
      (tester) async {
    // This is a correctness test, not a copy test. The disclosure and the code
    // must ship together: a sheet that still claims the app never touches the
    // device's location, next to a build that runs a background location
    // service, is a false statement to users and to the stores.
    await tester.pumpWidget(harness(Builder(
      builder: (context) => TextButton(
        onPressed: () => showLegalSheet(context),
        child: const Text('open'),
      ),
    )));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.textContaining('teilt keinen eigenen Standort'), findsNothing,
        reason: 'the watcher-only wording must not outlive the watcher-only build');
    expect(find.textContaining('Ortungsdienste'), findsWidgets);
    expect(find.textContaining('Im Hintergrund'), findsWidgets,
        reason: 'background behaviour is the part users cannot infer');
    expect(find.textContaining('wegwischst'), findsWidgets,
        reason: 'the swipe-away limit is a real behaviour people rely on');
    expect(find.textContaining('Play Services'), findsWidgets);
  });

  group('markup renderer', () {
    TextSpan render(String source) => richFromMarkup(source, const TextStyle());

    test('keeps plain text intact', () {
      expect(render('hello').toPlainText(), 'hello');
    });

    test('strips the tags it understands and keeps the words', () {
      final span = render('a <strong>b</strong> c <em>d</em> e <code>f</code>');
      expect(span.toPlainText(), 'a b c d e f');
    });

    test('applies the styles', () {
      final children = render('<strong>bold</strong>plain').children!.cast<TextSpan>();
      expect(children.first.style!.fontWeight, FontWeight.w700);
      expect(children.last.style!.fontWeight, isNot(FontWeight.w700));
    });

    test('an unknown tag survives as literal text rather than vanishing', () {
      // A new tag in the shared strings should be a visible bug, not silent loss.
      expect(render('a <b>x</b> c').toPlainText(), 'a <b>x</b> c');
    });
  });
}
