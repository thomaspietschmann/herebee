import 'package:flutter_test/flutter_test.dart';
import 'package:herebee/features/map/auto_fit.dart';

void main() {
  bool fit(AutoFit a, Set<String> seeds, {bool sharing = false, bool following = false}) =>
      a.shouldFit(seeds: seeds, sharing: sharing, following: following);

  test('fits when the first bee appears, then only for newcomers', () {
    final a = AutoFit();
    expect(fit(a, {}), isFalse, reason: 'nothing to fit yet');
    expect(fit(a, {'anna'}), isTrue);
    expect(fit(a, {'anna'}), isFalse, reason: 'a position update is not a new bee');
    expect(fit(a, {'anna', 'ben'}), isTrue);
    expect(fit(a, {'ben'}), isFalse, reason: 'someone leaving does not move the camera');
    expect(fit(a, {'ben', 'anna'}), isTrue, reason: 'coming back counts as arriving');
  });

  test('a gesture hands the camera to the user until they start sharing', () {
    final a = AutoFit();
    expect(fit(a, {'anna'}), isTrue);
    a.cameraTaken();
    expect(fit(a, {'anna', 'ben'}), isFalse);
    // Sharing starts: explicit intent, the next newcomer (ourselves) fits again.
    expect(fit(a, {'anna', 'ben'}, sharing: true), isTrue);
    expect(fit(a, {'anna', 'ben', 'me'}, sharing: true), isTrue);
    expect(fit(a, {'anna', 'ben', 'me'}, sharing: true), isFalse);
    // Sharing continuing is not a new intent: a gesture sticks again.
    a.cameraTaken();
    expect(fit(a, {'anna', 'ben', 'me', 'cid'}, sharing: true), isFalse);
    // Stop and start again re-arms.
    expect(fit(a, {'anna', 'ben', 'cid'}, sharing: false), isFalse);
    expect(fit(a, {'anna', 'ben', 'cid', 'me'}, sharing: true), isTrue);
  });

  test('never moves while following someone', () {
    final a = AutoFit();
    expect(fit(a, {'anna'}, following: true), isFalse);
    expect(fit(a, {'anna', 'ben'}, following: true), isFalse);
    expect(fit(a, {'anna', 'ben'}), isTrue, reason: 'once follow ends, newcomers fit');
  });
}
