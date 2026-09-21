/// A mangled link must fail visibly. Silently deriving a different valid room
/// from a truncated secret is the worst outcome: everything looks fine and
/// nobody is there.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:herebee/core/deep_links.dart';

void main() {
  const valid = 'ByxRdpvA5QovVHmew-gNMld8ocbrEDVaf6TJ7hM4XYI'; // 43 chars

  test('reads the secret from an https room link', () {
    expect(secretFromLink(Uri.parse('https://herebee.app/r/#$valid')), valid);
  });

  test('reads the secret from the fallback scheme', () {
    expect(secretFromLink(Uri.parse('herebee://r#$valid')), valid);
  });

  test('ignores the host, which decides nothing', () {
    // The app always talks to its configured origin, so the delivering host is
    // irrelevant. Accepting it is not a redirect.
    expect(secretFromLink(Uri.parse('https://example.test/r/#$valid')), valid);
  });

  test('rejects a truncated or padded secret', () {
    expect(secretFromLink(Uri.parse('https://herebee.app/r/#${valid.substring(0, 42)}')), isNull);
    expect(secretFromLink(Uri.parse('https://herebee.app/r/#${valid}A')), isNull);
  });

  test('rejects characters outside base64url', () {
    expect(secretFromLink(Uri.parse('https://herebee.app/r/#${'a' * 42}+')), isNull);
    expect(secretFromLink(Uri.parse('https://herebee.app/r/#${'a' * 42}/')), isNull);
  });

  test('returns null when there is no fragment at all', () {
    expect(secretFromLink(Uri.parse('https://herebee.app/r/')), isNull);
    expect(secretFromLink(Uri.parse('https://herebee.app/')), isNull);
  });

  group('looksLikeRoomLink', () {
    test('a room link is one, however it is shaped', () {
      expect(looksLikeRoomLink(Uri.parse('https://herebee.app/r/#$valid')), isTrue);
      expect(looksLikeRoomLink(Uri.parse('herebee://r#$valid')), isTrue);
      expect(looksLikeRoomLink(Uri.parse('https://herebee.app/r/')), isTrue,
          reason: 'a room link with a lost fragment is still a room link');
    });

    test('the bare site is not', () {
      expect(looksLikeRoomLink(Uri.parse('https://herebee.app/')), isFalse);
    });
  });
}
