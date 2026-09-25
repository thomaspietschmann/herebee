import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:herebee/core/peer_state.dart';
import 'package:herebee/core/types.dart';
import 'package:herebee/features/sheets/sheets.dart';
import 'package:herebee/l10n/app_localizations.dart';

LocUpdate fix({String? name}) =>
    LocUpdate(seed: 'p', lat: 1, lng: 2, acc: null, hdg: null, spd: null, at: 3, name: name);

void main() {
  test('a peer keeps its shared name only while its updates carry it', () {
    final peers = PeerStore()..upsert(fix(name: 'Anna'));
    expect(peers['p']!.sharedName, 'Anna');
    peers.upsert(fix());
    expect(peers['p']!.sharedName, isNull, reason: 'an update without a name means no longer shared');
    peers.upsert(fix(name: 'Lena'));
    expect(peers['p']!.sharedName, 'Lena');
  });

  Future<void> open(WidgetTester tester, void Function(bool) onAnswer) async {
    await tester.pumpWidget(MaterialApp(
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
            onPressed: () async => onAnswer(await askShareName(context, 'Anna')),
            child: const Text('open'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  testWidgets('asks before sharing and names the name', (tester) async {
    bool? answer;
    await open(tester, (a) => answer = a);
    expect(find.text('Namen teilen?'), findsOneWidget);
    expect(find.textContaining('„Anna“'), findsOneWidget);
    await tester.tap(find.text('Teilen'));
    await tester.pumpAndSettle();
    expect(answer, isTrue);
  });

  testWidgets('"just for me" declines, and the question cannot be swiped away', (tester) async {
    bool? answer;
    await open(tester, (a) => answer = a);
    await tester.tapAt(const Offset(10, 10)); // the barrier above the sheet
    await tester.pumpAndSettle();
    expect(find.text('Namen teilen?'), findsOneWidget);
    await tester.tap(find.text('Nur für mich'));
    await tester.pumpAndSettle();
    expect(answer, isFalse);
  });
}
