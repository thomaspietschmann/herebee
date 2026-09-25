import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:herebee/core/recent_rooms.dart';
import 'package:herebee/features/sheets/sheets.dart';
import 'package:herebee/features/start/start_screen.dart';
import 'package:herebee/l10n/app_localizations.dart';

/// Opens the rooms sheet from a button and captures what it returns.
Widget host(RecentRooms recent, void Function(RoomsChoice?) onResult) => MaterialApp(
      locale: const Locale('de'),
      localizationsDelegates: const [
        L.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: L.supportedLocales,
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () async => onResult(await showRoomsSheet(
              context,
              recent: recent,
              currentSecret: 'current',
              nameFor: (seed) => 'Biene $seed',
            )),
            child: const Text('open'),
          ),
        ),
      ),
    );

void main() {
  startScreenTests();

  testWidgets('lists remembered rooms by the peers met there and marks the current one',
      (tester) async {
    final recent = RecentRooms(MemorySecretStore());
    await recent.load();
    await recent.touch('other');
    await recent.sawPeers('other', ['x', 'y']);
    await recent.touch('current');

    await tester.pumpWidget(host(recent, (_) {}));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.text('Deine Räume'), findsOneWidget);
    expect(find.text('Neuen Raum öffnen'), findsOneWidget);
    expect(find.text('Biene x, Biene y'), findsOneWidget);
    expect(find.text('Noch niemanden getroffen'), findsOneWidget);
    expect(find.textContaining('Du bist hier'), findsOneWidget);
  });

  testWidgets('tapping a room returns its secret; the new-room button returns no secret',
      (tester) async {
    final recent = RecentRooms(MemorySecretStore());
    await recent.load();
    await recent.touch('other');
    await recent.sawPeers('other', ['x']);
    RoomsChoice? result;

    await tester.pumpWidget(host(recent, (r) => result = r));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Biene x'));
    await tester.pumpAndSettle();
    expect(result?.secret, 'other');

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Neuen Raum öffnen'));
    await tester.pumpAndSettle();
    expect(result, isNotNull);
    expect(result!.secret, isNull);
  });

  testWidgets('the close button forgets a room immediately, forget-all empties the list',
      (tester) async {
    final recent = RecentRooms(MemorySecretStore());
    await recent.load();
    await recent.touch('a');
    await recent.sawPeers('a', ['x']);
    await recent.touch('b');
    await recent.sawPeers('b', ['y']);

    await tester.pumpWidget(host(recent, (_) {}));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Raum vergessen').first);
    await tester.pumpAndSettle();
    expect(recent.rooms.length, 1);
    expect(find.text('Biene y'), findsNothing);
    expect(find.text('Biene x'), findsOneWidget);

    await tester.tap(find.text('Alle vergessen'));
    await tester.pumpAndSettle();
    expect(recent.rooms, isEmpty);
    expect(find.text('Zuletzt betreten'), findsNothing);
    expect(find.text('Neuen Raum öffnen'), findsOneWidget);
  });

  testWidgets('the open room is marked, cannot be forgotten and survives forget-all',
      (tester) async {
    final recent = RecentRooms(MemorySecretStore());
    await recent.load();
    await recent.touch('a');
    await recent.sawPeers('a', ['x']);
    await recent.touch('current');
    await recent.sawPeers('current', ['me']);

    await tester.pumpWidget(host(recent, (_) {}));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.text('Du bist hier'), findsOneWidget);
    expect(find.byTooltip('Raum vergessen'), findsOneWidget,
        reason: 'only the other room has a close button');

    await tester.tap(find.text('Alle vergessen'));
    await tester.pumpAndSettle();
    expect(recent.rooms.map((r) => r.secret), ['current']);
    expect(find.text('Biene me'), findsOneWidget);
    expect(find.text('Biene x'), findsNothing);
    expect(find.text('Alle vergessen'), findsNothing,
        reason: 'nothing left that could be forgotten');
  });
}

Widget startHost(RecentRooms recent, void Function(RoomsChoice) onChoose) => MaterialApp(
      locale: const Locale('de'),
      localizationsDelegates: const [
        L.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: L.supportedLocales,
      home: StartScreen(recent: recent, nameFor: (seed) => 'Biene $seed', onChoose: onChoose),
    );

void startScreenTests() {
  testWidgets('start screen offers the remembered rooms and a new one, and reports the pick',
      (tester) async {
    final recent = RecentRooms(MemorySecretStore());
    await recent.load();
    await recent.touch('a');
    await recent.sawPeers('a', ['x']);
    RoomsChoice? picked;

    await tester.pumpWidget(startHost(recent, (c) => picked = c));
    await tester.pumpAndSettle();
    expect(find.text('Deine Räume'), findsOneWidget);
    expect(find.text('Biene x'), findsOneWidget);
    expect(find.textContaining('Du bist hier'), findsNothing,
        reason: 'no room is open yet, so none is current');

    await tester.tap(find.text('Biene x'));
    expect(picked?.secret, 'a');
    await tester.tap(find.text('Neuen Raum öffnen'));
    expect(picked, isNotNull);
    expect(picked!.secret, isNull);
  });
}
