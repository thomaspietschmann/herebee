import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:herebee/core/style_guard.dart';

Map<String, dynamic> styleWith({
  Object? glyphs = 'https://herebee.app/basemaps/fonts/{fontstack}/{range}.pbf',
  Object? sprite = 'https://herebee.app/basemaps/sprites/v4/light',
  Map<String, dynamic>? sources,
}) => {
  'version': 8,
  'glyphs': glyphs,
  'sprite': sprite,
  'sources':
      sources ??
      {
        'protomaps': {
          'type': 'vector',
          'url': 'pmtiles://https://herebee.app/tiles/basemap.pmtiles?v=1',
          'attribution': '<a href="https://protomaps.com">Protomaps</a>',
        },
      },
  'layers': [
    {'id': 'bg', 'type': 'background'},
  ],
};

void main() {
  final guard = StyleGuard('https://herebee.app');

  group('isAllowedUrl accepts', () {
    for (final url in [
      'https://herebee.app/tiles/{z}/{x}/{y}.pbf',
      'https://herebee.app',
      'https://herebee.app?x=1',
      'HTTPS://HereBee.app/x',
      '/basemaps/fonts/{fontstack}/{range}.pbf',
      'sprites/light',
      '//herebee.app/x',
      'pmtiles://https://herebee.app/tiles/basemap.pmtiles',
    ]) {
      test(url, () => expect(guard.isAllowedUrl(url), isTrue));
    }
  });

  group('isAllowedUrl rejects', () {
    for (final url in [
      'https://evil.example/tiles/{z}/{x}/{y}.pbf',
      'https://herebee.app.evil.example/x',
      'https://herebee.app@evil.example/x',
      'https://herebee.app:8443/x',
      'https://herebee.app:443/x',
      'http://herebee.app/x',
      'wss://herebee.app/x',
      'mapbox://styles/x',
      'file:///etc/hosts',
      'https:evil.example',
      '//evil.example/x',
      '//herebee.app:8443/x',
      'pmtiles://https://evil.example/basemap.pmtiles',
      'pmtiles:///tiles/basemap.pmtiles',
      'pmtiles://http://herebee.app/basemap.pmtiles',
      'https://evil.example\\@herebee.app/x',
      '/\\evil.example/x',
      'https://herebee.app /x',
    ]) {
      test(url, () => expect(guard.isAllowedUrl(url), isFalse));
    }
  });

  test('dev http origin with port', () {
    final dev = StyleGuard('http://localhost:3000');
    expect(dev.isAllowedUrl('http://localhost:3000/tiles/a.pmtiles'), isTrue);
    expect(dev.isAllowedUrl('pmtiles://http://localhost:3000/tiles/a.pmtiles'), isTrue);
    expect(dev.isAllowedUrl('http://localhost:3001/tiles/a.pmtiles'), isFalse);
    expect(dev.isAllowedUrl('http://localhost/tiles/a.pmtiles'), isFalse);
    expect(dev.isAllowedUrl('https://localhost:3000/tiles/a.pmtiles'), isFalse);
  });

  group('validate', () {
    void ok(Map<String, dynamic> s) => expect(() => guard.validate(s), returnsNormally);
    void bad(Map<String, dynamic> s) =>
        expect(() => guard.validate(s), throwsA(isA<StyleRejected>()));

    test('production-like style', () => ok(styleWith()));

    test(
      'relative glyphs and sprite',
      () => ok(styleWith(glyphs: '/fonts/{fontstack}/{range}.pbf', sprite: 'sprites/light')),
    );

    test('sprite list on origin', () {
      ok(
        styleWith(
          sprite: [
            {'id': 'default', 'url': 'https://herebee.app/sprites/light'},
            {'id': 'extra', 'url': '/sprites/extra'},
          ],
        ),
      );
    });

    test('sprite list with one foreign entry', () {
      bad(
        styleWith(
          sprite: [
            {'id': 'default', 'url': 'https://herebee.app/sprites/light'},
            {'id': 'extra', 'url': 'https://evil.example/sprites/extra'},
          ],
        ),
      );
    });

    test(
      'foreign glyphs',
      () => bad(styleWith(glyphs: 'https://evil.example/{fontstack}/{range}.pbf')),
    );

    test('foreign sprite string', () => bad(styleWith(sprite: '//evil.example/sprite')));

    test('tiles array with one foreign entry', () {
      bad(
        styleWith(
          sources: {
            'v': {
              'type': 'vector',
              'tiles': [
                'https://herebee.app/t/{z}/{x}/{y}.pbf',
                'https://evil.example/t/{z}/{x}/{y}.pbf',
              ],
            },
          },
        ),
      );
    });

    test('tiles array all on origin', () {
      ok(
        styleWith(
          sources: {
            'v': {
              'type': 'vector',
              'tiles': ['https://herebee.app/t/{z}/{x}/{y}.pbf', '/t2/{z}/{x}/{y}.pbf'],
            },
          },
        ),
      );
    });

    test('second source foreign', () {
      bad(
        styleWith(
          sources: {
            'a': {'type': 'vector', 'url': 'pmtiles://https://herebee.app/a.pmtiles'},
            'b': {'type': 'raster', 'url': 'https://herebee.app:444/b.json'},
          },
        ),
      );
    });

    test('geojson data url foreign', () {
      bad(
        styleWith(
          sources: {
            'g': {'type': 'geojson', 'data': 'https://evil.example/points.geojson'},
          },
        ),
      );
    });

    test('image source urls', () {
      bad(
        styleWith(
          sources: {
            'i': {
              'type': 'video',
              'urls': ['/v.mp4', 'http://herebee.app/v.webm'],
            },
          },
        ),
      );
    });

    test('url hidden in a layer', () {
      final s = styleWith();
      s['layers'] = <Object>[
        ...s['layers'] as List,
        {
          'id': 'x',
          'type': 'symbol',
          'metadata': {'anything': 'https://evil.example/beacon'},
        },
      ];
      bad(s);
    });

    test('non-object document', () {
      expect(() => guard.validate([1, 2]), throwsA(isA<StyleRejected>()));
    });
  });

  group('validateJson', () {
    test('invalid json', () {
      expect(() => guard.validateJson('{nope'), throwsA(isA<StyleRejected>()));
    });

    test('duplicate keys cannot smuggle a foreign url', () {
      const body =
          '{"version":8,"glyphs":"https://evil.example/{fontstack}/{range}.pbf",'
          '"glyphs":"https://herebee.app/{fontstack}/{range}.pbf","sources":{},"layers":[]}';
      final out = guard.validateJson(body);
      expect(out, isNot(contains('evil.example')));
      expect(out.trimLeft().startsWith('{'), isTrue);
    });

    test('returns equivalent json', () {
      final s = styleWith();
      expect(jsonDecode(guard.validateJson(jsonEncode(s))), s);
    });
  });

  group('fetch', () {
    late HttpServer server;
    late String origin;
    late int status;
    late String body;
    String? location;

    setUp(() async {
      status = 200;
      location = null;
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      origin = 'http://127.0.0.1:${server.port}';
      server.listen((req) {
        req.response.statusCode = status;
        if (location != null) req.response.headers.set('location', location!);
        req.response.write(body);
        req.response.close();
      });
    });

    tearDown(() => server.close(force: true));

    test('accepts same-origin style', () async {
      body = jsonEncode(
        styleWith(
          glyphs: '$origin/fonts/{fontstack}/{range}.pbf',
          sprite: '$origin/sprites/light',
          sources: {
            'p': {'type': 'vector', 'url': 'pmtiles://$origin/tiles/basemap.pmtiles'},
          },
        ),
      );
      final out = await StyleGuard(origin).fetch('$origin/style/en.json');
      expect(jsonDecode(out), jsonDecode(body));
    });

    test('rejects style pointing elsewhere', () async {
      body = jsonEncode(styleWith());
      await expectLater(
        StyleGuard(origin).fetch('$origin/style/en.json'),
        throwsA(isA<StyleRejected>()),
      );
    });

    test('rejects http error', () async {
      status = 500;
      body = '{}';
      await expectLater(
        StyleGuard(origin).fetch('$origin/style/en.json'),
        throwsA(isA<StyleRejected>()),
      );
    });

    test('does not follow redirects', () async {
      status = 302;
      location = 'https://evil.example/style.json';
      body = '';
      await expectLater(
        StyleGuard(origin).fetch('$origin/style/en.json'),
        throwsA(isA<StyleRejected>()),
      );
    });

    test('rejects invalid json', () async {
      body = 'not json';
      await expectLater(
        StyleGuard(origin).fetch('$origin/style/en.json'),
        throwsA(isA<StyleRejected>()),
      );
    });

    test('rejects style url off origin', () async {
      body = '{}';
      await expectLater(
        StyleGuard(origin).fetch('http://127.0.0.2:${server.port}/style/en.json'),
        throwsA(isA<StyleRejected>()),
      );
    });

    test('rejects unreachable server', () async {
      await server.close(force: true);
      await expectLater(
        StyleGuard(origin).fetch('$origin/style/en.json'),
        throwsA(isA<StyleRejected>()),
      );
    });
  });
}
