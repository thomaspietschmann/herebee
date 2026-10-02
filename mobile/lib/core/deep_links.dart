/// Reading a room out of a link.
///
/// The secret lives in the URL fragment, which is the whole point: a fragment is
/// never sent to a server, so the capability travels in the link without the
/// relay ever seeing it. Both link shapes carry it the same way:
///
///   `https://herebee.app/r/#<secret>`           (Universal Links / App Links)
///   `https://other.example/r/#<secret>`         (pasted; a room on another server)
///   `herebee://r#<secret>`                      (fallback scheme, configured server)
///   `herebee://r?server=<origin>#<secret>`      (fallback scheme, named server)
///
/// The link's server decides where the room lives: the same secret on another
/// server is a different, empty room. But a link must never move anyone to
/// another server silently, so the caller warns before following a server that
/// is not the official one (see [linkOrigin]).
library;

import '../app_config.dart';

/// Length of a base64url-encoded 32-byte secret, unpadded.
const int _secretLength = 43;

final RegExp _secretPattern = RegExp('^[A-Za-z0-9_-]{$_secretLength}\$');

/// The room secret a link carries, or null if it carries none.
///
/// Strict on purpose. A truncated or mangled link must fail visibly rather than
/// derive some other valid room id and drop the user into an empty room nobody
/// else can reach.
String? secretFromLink(Uri uri) {
  final fragment = uri.fragment;
  if (fragment.isEmpty) return null;
  return _secretPattern.hasMatch(fragment) ? fragment : null;
}

/// The server a room link names, normalized, or null when it names none (the
/// `herebee://` scheme without `server=`, or something that cannot be a
/// HereBee server). Null means "use the configured server".
String? linkOrigin(Uri uri) {
  if (uri.scheme == 'http' || uri.scheme == 'https') return normalizeOrigin(uri.origin);
  final server = uri.queryParameters['server'];
  return server == null ? null : normalizeOrigin(server);
}

/// Whether a link was meant to open a room at all.
///
/// Distinguishes "opened from the home screen" (no link — mint a fresh room,
/// like the web client does for "/") from "followed a room link that is broken"
/// (say so, because the user expected a specific room).
bool looksLikeRoomLink(Uri uri) =>
    uri.fragment.isNotEmpty || uri.path.startsWith('/r') || uri.host == 'r' || uri.path == 'r';

/// A room link somewhere inside pasted text: `https://…#secret` or
/// `herebee://…#secret`.
///
/// The secret is taken as the whole base64url run after the `#`, so trailing
/// punctuation from a chat message ("here: https://…#abc.") falls away, while
/// a truncated or overlong run still fails the same strict length check.
final RegExp _linkInText = RegExp(r'(?:https?|herebee)://[^\s#]*#([A-Za-z0-9_-]+)');

/// The room secret of the first room link in [text], or null if there is none.
///
/// For links copied out of a chat while Universal Links are not active: the
/// message often carries more than the bare link.
String? secretFromText(String text) => roomFromText(text)?.secret;

/// The first room link in [text]: its secret and the server it names (null for
/// "the configured server").
({String secret, String? origin})? roomFromText(String text) {
  for (final match in _linkInText.allMatches(text)) {
    final candidate = match.group(1)!;
    if (!_secretPattern.hasMatch(candidate)) continue;
    final link = text.substring(match.start, match.end);
    Uri? uri;
    try {
      uri = Uri.parse(link);
    } on FormatException {
      uri = null;
    }
    return (secret: candidate, origin: uri == null ? null : linkOrigin(uri));
  }
  return null;
}
