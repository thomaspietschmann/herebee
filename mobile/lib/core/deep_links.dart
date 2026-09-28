/// Reading a room out of a link.
///
/// The secret lives in the URL fragment, which is the whole point: a fragment is
/// never sent to a server, so the capability travels in the link without the
/// relay ever seeing it. Both link shapes carry it the same way:
///
///   `https://herebee.app/r/#<secret>`   (Universal Links / App Links)
///   `herebee://r#<secret>`              (fallback scheme)
///
/// The link's HOST is deliberately ignored. It decides nothing: the app always
/// talks to its configured origin, never to whatever host delivered the link, so
/// a link from somewhere else cannot redirect anyone anywhere.
library;

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
String? secretFromText(String text) {
  for (final match in _linkInText.allMatches(text)) {
    final candidate = match.group(1)!;
    if (_secretPattern.hasMatch(candidate)) return candidate;
  }
  return null;
}
