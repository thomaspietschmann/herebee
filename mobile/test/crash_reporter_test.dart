/// Uncaught Dart errors: asked once, sent only on "Send", redacted, and in the
/// format server/src/crash.ts accepts.
library;

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:herebee/app_config.dart';
import 'package:herebee/core/crash_reporter.dart';
import 'package:herebee/features/crash/crash_prompt.dart';
import 'package:herebee/l10n/app_localizations.dart';

const String secret = 'ZuIRKvwizU43UH23hkeFKy8rA8R4dbX6DXmIVd31apc';

/// Keys server/src/crash.ts's strict schema accepts.
const Set<String> serverFields = {
  'platform', 'source', 'osVersion', 'reportId', 'appVersionCode', 'appVersionName', 'packageName',
  'androidVersion', 'brand', 'phoneModel', 'stackTrace', 'stackTraceHash', 'userComment', 'crashDate',
};

class Posted {
  Posted(this.url, this.body);
  final Uri url;
  final Map<String, dynamic> body;
}

void main() {
  group('redaction', () {
    test('room keys, app links and coordinates never leave the device', () {
      final out = redactReport(
          'at 52.520008,13.404954 open https://herebee.app/r/#$secret or herebee://r#$secret ok');
      expect(out, isNot(contains(secret)));
      expect(out, isNot(contains('52.520008')));
      expect(out, contains('https://herebee.app/r/#[redacted]'));
      expect(out, contains('herebee://[redacted]'));
      expect(out, contains('[number],[number]'));
      expect(out, endsWith(' ok'));
    });

    test('ordinary trace lines stay readable', () {
      const line = '#0 RoomController.enter (package:herebee/features/room/room_controller.dart:264:5)';
      expect(redactReport(line), line);
    });
  });

  group('payload', () {
    final crash = PendingCrash(
      error: 'StateError: Bad state: at 52.520008,13.404954',
      stack: '#0 main (package:herebee/main.dart:1:1)',
      at: DateTime.utc(2026, 10, 2, 12),
    );

    test('only fields the server accepts, marked as a Dart error', () {
      final p = crash.payload(comment: 'tapped share at https://herebee.app/r/#$secret');
      expect(serverFields.containsAll(p.keys), isTrue, reason: '${p.keys}');
      expect(p['source'], 'dart');
      expect(p['appVersionName'], AppConfig.clientVersion);
      expect(p['crashDate'], '2026-10-02T12:00:00.000Z');
      expect(p['stackTrace'], startsWith('StateError: Bad state: at [number],[number]'));
      expect(p['userComment'], 'tapped share at https://herebee.app/r/#[redacted]');
    });

    test('no empty comment, long traces are capped', () {
      expect(crash.payload(comment: '   ').containsKey('userComment'), isFalse);
      final long = PendingCrash(error: 'E', stack: 'x' * 50000, at: DateTime.utc(2026));
      expect(long.payload()['stackTrace']!.length, 32000);
    });
  });

  group('reporter', () {
    test('keeps only the first error and asks once per session', () {
      final r = CrashReporter(serverOrigin: () => AppConfig.officialOrigin, post: (_, _) async => 204);
      r.record(StateError('one'), StackTrace.current);
      r.record(StateError('two'), StackTrace.current);
      expect(r.pending.value!.error, contains('one'));
      expect(r.take(), isNotNull);
      r.record(StateError('three'), StackTrace.current);
      expect(r.pending.value, isNull, reason: 'already asked in this session');
    });

    test('sends to the configured server, read at send time', () async {
      var origin = AppConfig.officialOrigin;
      final posted = <Posted>[];
      final r = CrashReporter(
        serverOrigin: () => origin,
        post: (url, body) async {
          posted.add(Posted(url, jsonDecode(body) as Map<String, dynamic>));
          return 204;
        },
      );
      r.record(StateError('boom'), StackTrace.current);
      final crash = r.take()!;
      origin = 'https://other.example';
      expect(await r.send(crash), isTrue);
      expect(posted.single.url.toString(), 'https://other.example/api/crash');
    });

    test('a refused or failed send is reported as such', () async {
      final refused = CrashReporter(serverOrigin: () => AppConfig.officialOrigin, post: (_, _) async => 503);
      refused.record(StateError('x'), null);
      expect(await refused.send(refused.take()!), isFalse);
      final offline = CrashReporter(
          serverOrigin: () => AppConfig.officialOrigin, post: (_, _) async => throw Exception('offline'));
      offline.record(StateError('x'), null);
      expect(await offline.send(offline.take()!), isFalse);
    });
  });

  group('dialog', () {
    late List<Posted> posted;
    late CrashReporter reporter;

    Widget app() {
      final nav = GlobalKey<NavigatorState>();
      return MaterialApp(
        locale: const Locale('de'),
        localizationsDelegates: const [
          L.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: L.supportedLocales,
        navigatorKey: nav,
        builder: (context, child) =>
            CrashPrompt(reporter: reporter, navigatorKey: nav, child: child!),
        home: const Scaffold(body: Text('room')),
      );
    }

    setUp(() {
      posted = [];
      reporter = CrashReporter(
        serverOrigin: () => 'https://other.example',
        post: (url, body) async {
          posted.add(Posted(url, jsonDecode(body) as Map<String, dynamic>));
          return 204;
        },
      );
    });

    testWidgets('asks, names the server, and sends with the comment', (tester) async {
      await tester.pumpWidget(app());
      reporter.record(StateError('boom'), StackTrace.current);
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('crash-dialog')), findsOneWidget);
      expect(find.text('In HereBee ist ein Fehler aufgetreten'), findsOneWidget);
      expect(find.textContaining('other.example'), findsOneWidget);
      expect(posted, isEmpty, reason: 'nothing before Send');

      await tester.enterText(find.byKey(const ValueKey('crash-comment')), 'Raum gewechselt');
      await tester.tap(find.byKey(const ValueKey('crash-send')));
      await tester.pumpAndSettle();

      expect(posted.single.url.toString(), 'https://other.example/api/crash');
      expect(posted.single.body['userComment'], 'Raum gewechselt');
      expect(posted.single.body['stackTrace'], contains('boom'));
      expect(find.text('Danke, der Fehlerbericht wurde gesendet.'), findsOneWidget,
          reason: 'shown in the dialog, not in a snackbar that a modal sheet could hide');
      await tester.tap(find.byKey(const ValueKey('crash-ok')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('crash-dialog')), findsNothing);

      // A second error in the same session is not asked about again.
      reporter.record(StateError('again'), StackTrace.current);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('crash-dialog')), findsNothing);
    });

    testWidgets('an error in an idle app schedules the frame that shows the question', (tester) async {
      await tester.pumpWidget(app());
      await tester.pumpAndSettle();
      expect(tester.binding.hasScheduledFrame, isFalse, reason: 'the app is idle');
      reporter.record(StateError('idle'), StackTrace.current);
      expect(tester.binding.hasScheduledFrame, isTrue,
          reason: 'without a frame the post-frame callback never runs');
      await tester.pump();
      await tester.pump();
      expect(find.byKey(const ValueKey('crash-dialog')), findsOneWidget);
    });

    testWidgets("Don't send sends nothing", (tester) async {
      await tester.pumpWidget(app());
      reporter.record(StateError('boom'), StackTrace.current);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('crash-dont-send')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('crash-dialog')), findsNothing);
      expect(posted, isEmpty);
    });

    testWidgets('an error before the first frame is asked about once the app is up', (tester) async {
      reporter.record(StateError('early'), StackTrace.current);
      await tester.pumpWidget(app());
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('crash-dialog')), findsOneWidget);
    });
  });
}
