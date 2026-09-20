/// Where the app talks to. Everything is one origin by design: the relay, the
/// map style, the glyphs, the sprites and the tiles all come from HereBee's own
/// host, so no third party ever learns which areas a user pans across.
///
/// Override for development with, e.g.
///   flutter run --dart-define=HEREBEE_ORIGIN=http://10.0.2.2:3000   (emulator)
///   flutter run --dart-define=HEREBEE_ORIGIN=http://localhost:3000  (simulator)
library;

class AppConfig {
  const AppConfig._();

  static const String origin = String.fromEnvironment(
    'HEREBEE_ORIGIN',
    defaultValue: 'https://herebee.app',
  );

  /// Sent as X-HereBee-Client on the WebSocket upgrade. Carries no identity.
  static const String clientVersion = '1.0.0';

  static String get wsUrl {
    final u = Uri.parse(origin);
    final scheme = u.scheme == 'https' ? 'wss' : 'ws';
    return '$scheme://${u.authority}/ws';
  }

  /// Generated per UI language by scripts/gen-style.ts; the server substitutes
  /// the real origin per request, so the URLs inside are absolute and ready.
  static String styleUrl(String languageCode) => '$origin/style/$languageCode.json';

  /// Shareable room link. The secret lives in the fragment, which is never sent
  /// to any server.
  static String roomLink(String secret) => '$origin/r/#$secret';
}
