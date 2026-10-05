/// Where the app talks to. Everything for one room comes from one origin by
/// design: the relay, the map style, the glyphs, the sprites and the tiles, so
/// no third party ever learns which areas a user pans across.
///
/// That origin is the official server unless the user picked another one that
/// runs the HereBee web app, or opened a room link naming another one. Both
/// paths warn first (see showServerWarning in features/sheets/sheets.dart):
/// payloads stay end-to-end encrypted, but the operator sees IPs, room timing
/// and, through the tiles, roughly where people look.
///
/// Override the default for development with, e.g.
///   flutter run --dart-define=HEREBEE_ORIGIN=http://10.0.2.2:3000   (emulator)
///   flutter run --dart-define=HEREBEE_ORIGIN=http://localhost:3000  (simulator)
library;

import 'package:flutter/foundation.dart';

class AppConfig {
  const AppConfig._();

  /// The server operated under HereBee's privacy statement. Keep in sync with
  /// shared/server.ts.
  static const String officialOrigin = 'https://herebee.app';

  /// The server used when the user has not chosen one. The official one,
  /// except in a development build pointed at a local relay.
  static const String defaultOrigin = String.fromEnvironment(
    'HEREBEE_ORIGIN',
    defaultValue: officialOrigin,
  );

  /// Sent as X-HereBee-Client on the WebSocket upgrade. Carries no identity.
  static const String clientVersion = '0.0.25';

  static bool isOfficial(String origin) => origin == officialOrigin;

  /// The host shown to people, e.g. `herebee.example.org` or `localhost:3100`.
  static String hostOf(String origin) => Uri.parse(origin).authority;

  static String wsUrl(String origin) {
    final u = Uri.parse(origin);
    final scheme = u.scheme == 'https' ? 'wss' : 'ws';
    return '$scheme://${u.authority}/ws';
  }

  /// Generated per UI language and map theme by scripts/gen-style.ts; the
  /// server substitutes the real origin per request, so the URLs inside are
  /// absolute and ready. [theme] is a resolved map theme ('light', 'dark',
  /// 'synthwave', 'tron', ...); light lives at the top level, the others in a folder.
  static String styleUrl(String origin, String languageCode, {String theme = 'light'}) =>
      theme == 'light' ? '$origin/style/$languageCode.json' : '$origin/style/$theme/$languageCode.json';

  /// Shareable room link. The secret lives in the fragment, which is never sent
  /// to any server; the host says which server the room lives on.
  static String roomLink(String origin, String secret) => '$origin/r/#$secret';

  /// Liveness endpoint every HereBee server answers; used to check a server
  /// before switching to it.
  static String healthUrl(String origin) => '$origin/healthz';
}

/// Canonical `scheme://host[:port]` for what a person typed or a link carried,
/// or null if it cannot be a HereBee server.
///
/// A bare host gets `https://`. Plain `http://` is accepted only for a local
/// development relay in a debug build: release builds refuse cleartext on both
/// platforms anyway, and a public server without TLS would expose even the
/// room ids. Paths, queries, fragments and credentials are never part of an
/// origin.
String? normalizeOrigin(String input, {bool allowLocalHttp = kDebugMode}) {
  var s = input.trim();
  if (s.isEmpty) return null;
  if (!s.contains('://')) s = 'https://$s';
  final Uri u;
  try {
    u = Uri.parse(s);
  } on FormatException {
    return null;
  }
  if (u.host.isEmpty || u.userInfo.isNotEmpty) return null;
  if (u.host.contains(RegExp(r'[^a-zA-Z0-9.\-:]'))) return null;
  final scheme = u.scheme.toLowerCase();
  if (scheme == 'http') {
    if (!allowLocalHttp || !_isLocalHost(u.host)) return null;
  } else if (scheme != 'https') {
    return null;
  }
  final host = u.host.toLowerCase();
  final hostPart = host.contains(':') ? '[$host]' : host;
  final port = u.hasPort && u.port != (scheme == 'https' ? 443 : 80) ? ':${u.port}' : '';
  return '$scheme://$hostPart$port';
}

bool _isLocalHost(String host) {
  final h = host.toLowerCase();
  return h == 'localhost' ||
      h == '127.0.0.1' ||
      h == '::1' ||
      h == '10.0.2.2' ||
      h.endsWith('.local') ||
      RegExp(r'^(10|192\.168|172\.(1[6-9]|2\d|3[01]))\.').hasMatch(h);
}
