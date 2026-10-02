/// Choosing a server other than the official one, and links that name one.
///
/// A room is its secret AND its server: the same secret elsewhere is a
/// different, empty room. So the server must survive every path a room takes
/// (link, paste, recent list), and none of them may switch servers silently.
library;

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:herebee/app_config.dart';
import 'package:herebee/core/deep_links.dart';
import 'package:herebee/core/recent_rooms.dart';
import 'package:herebee/core/storage.dart';
import 'package:herebee/features/sheets/sheets.dart';
import 'package:herebee/l10n/app_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

const String secret = 'ZuIRKvwizU43UH23hkeFKy8rA8R4dbX6DXmIVd31apc';

void main() {
  group('normalizeOrigin', () {
    test('a bare host becomes an https origin', () {
      expect(normalizeOrigin('herebee.example.org'), 'https://herebee.example.org');
      expect(normalizeOrigin('  HereBee.Example.ORG/r/#abc '), 'https://herebee.example.org');
      expect(normalizeOrigin('https://herebee.example.org:8443/x?y'), 'https://herebee.example.org:8443');
      expect(normalizeOrigin('https://herebee.app:443'), AppConfig.officialOrigin);
    });

    test('rejects what cannot be a server', () {
      expect(normalizeOrigin(''), isNull);
      expect(normalizeOrigin('ftp://herebee.example.org'), isNull);
      expect(normalizeOrigin('https://user:pw@herebee.example.org'), isNull);
      expect(normalizeOrigin('https://'), isNull);
      expect(normalizeOrigin('herebee app'), isNull);
    });

    test('cleartext only for a local relay, and only when allowed', () {
      expect(normalizeOrigin('http://herebee.example.org', allowLocalHttp: true), isNull);
      expect(normalizeOrigin('http://localhost:3100', allowLocalHttp: true), 'http://localhost:3100');
      expect(normalizeOrigin('http://10.0.2.2:3100', allowLocalHttp: true), 'http://10.0.2.2:3100');
      expect(normalizeOrigin('http://localhost:3100', allowLocalHttp: false), isNull);
    });
  });

  group('links name their server', () {
    test('an https link names its own host', () {
      expect(linkOrigin(Uri.parse('https://herebee.app/r/#$secret')), AppConfig.officialOrigin);
      expect(linkOrigin(Uri.parse('https://other.example/r/#$secret')), 'https://other.example');
    });

    test('the app scheme names a server only through server=', () {
      expect(linkOrigin(Uri.parse('herebee://r#$secret')), isNull);
      expect(
        linkOrigin(Uri.parse('herebee://r?server=${Uri.encodeComponent('https://other.example')}#$secret')),
        'https://other.example',
      );
      expect(linkOrigin(Uri.parse('herebee://r?server=ftp%3A%2F%2Fx#$secret')), isNull);
    });

    test('a pasted link keeps its server', () {
      final room = roomFromText('Komm: https://other.example/r/#$secret bis gleich');
      expect(room?.secret, secret);
      expect(room?.origin, 'https://other.example');
      expect(roomFromText('herebee://r#$secret')?.origin, isNull);
    });
  });

  test('a room link carries the room\'s server', () {
    expect(AppConfig.roomLink('https://other.example', secret), 'https://other.example/r/#$secret');
    expect(AppConfig.wsUrl('https://other.example'), 'wss://other.example/ws');
  });

  group('recent rooms remember the server', () {
    test('round trip through the store', () async {
      final store = MemorySecretStore();
      final rooms = RecentRooms(store);
      await rooms.touch(secret, roomId: 'rid', origin: 'https://other.example');
      final reloaded = RecentRooms(store);
      await reloaded.load();
      expect(reloaded.rooms.single.origin, 'https://other.example');
    });

    test('entries from before servers were selectable are on the default server', () {
      final room = RecentRoom.fromJson({'s': secret, 't': 0});
      expect(room?.origin, AppConfig.defaultOrigin);
    });
  });

  group('configured server', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    test('defaults to the built-in one and stores only a real choice', () async {
      final storage = await Storage.open(device: MemorySecretStore());
      expect(storage.serverOrigin, AppConfig.defaultOrigin);
      expect(storage.serverChosen, isFalse);

      await storage.setServerOrigin('https://other.example');
      expect(storage.serverOrigin, 'https://other.example');
      expect((await SharedPreferences.getInstance()).getString(serverOriginKey), 'https://other.example');

      await storage.setServerOrigin(null);
      expect(storage.serverOrigin, AppConfig.defaultOrigin);
      expect(storage.serverChosen, isFalse);
    });

    test('the server in effect is mirrored for the native crash reporter', () async {
      final storage = await Storage.open(device: MemorySecretStore());
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString(reportOriginKey), AppConfig.defaultOrigin, reason: 'written on open');
      await storage.setServerOrigin('https://other.example');
      expect(prefs.getString(reportOriginKey), 'https://other.example');
      await storage.setServerOrigin(null);
      expect(prefs.getString(reportOriginKey), AppConfig.defaultOrigin);
    });

    test('a corrupt stored value falls back to the default', () async {
      SharedPreferences.setMockInitialValues({serverOriginKey: 'not a server'});
      final storage = await Storage.open(device: MemorySecretStore());
      expect(storage.serverOrigin, AppConfig.defaultOrigin);
    });
  });

  group('warning', () {
    Widget host(void Function(bool) onResult, {bool fromLink = true}) => MaterialApp(
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
                onPressed: () async => onResult(
                    await showServerWarning(context, origin: 'https://other.example', fromLink: fromLink)),
                child: const Text('open'),
              ),
            ),
          ),
        );

    testWidgets('names the server and says privacy is not guaranteed', (tester) async {
      bool? result;
      await tester.pumpWidget(host((r) => result = r));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      expect(find.text('Nicht der offizielle Server'), findsOneWidget);
      expect(find.textContaining('other.example', findRichText: true), findsOneWidget);
      expect(find.textContaining('nicht gewährleistet', findRichText: true), findsOneWidget);
      expect(find.text('Dieser Link nutzt einen anderen Server als den offiziellen.'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('server-warning-cancel')));
      await tester.pumpAndSettle();
      expect(result, isFalse);
    });

    testWidgets('continuing is an explicit choice', (tester) async {
      bool? result;
      await tester.pumpWidget(host((r) => result = r, fromLink: false));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(find.text('Dieser Link nutzt einen anderen Server als den offiziellen.'), findsNothing);

      await tester.tap(find.byKey(const ValueKey('server-warning-continue')));
      await tester.pumpAndSettle();
      expect(result, isTrue);
    });
  });
}
