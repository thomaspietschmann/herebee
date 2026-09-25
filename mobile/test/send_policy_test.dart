import 'package:flutter_test/flutter_test.dart';
import 'package:herebee/core/send_policy.dart';

void main() {
  late DateTime now;
  late SendPolicy p;

  setUp(() {
    now = DateTime(2026, 9, 25, 12);
    p = SendPolicy(clock: () => now);
  });

  void tick(Duration d) => now = now.add(d);

  test('foreground is always the live profile, moving or not', () {
    p.onFix(lat: 52.52, lng: 13.405);
    tick(const Duration(minutes: 5));
    expect(p.stationary, isTrue);
    expect(p.profile, SendPolicy.foregroundProfile);
  });

  test('background starts as moving and becomes still after 30 s at rest', () {
    p.onFix(lat: 52.52, lng: 13.405);
    p.setForeground(false);
    expect(p.profile, SendPolicy.backgroundMoving);
    tick(const Duration(seconds: 29));
    expect(p.profile, SendPolicy.backgroundMoving);
    tick(const Duration(seconds: 1));
    expect(p.profile, SendPolicy.backgroundStill);
  });

  test('stillness needs no fixes at all: time alone is enough', () {
    p.onFix(lat: 52.52, lng: 13.405);
    p.setForeground(false);
    tick(const Duration(minutes: 1));
    expect(p.profile, SendPolicy.backgroundStill,
        reason: 'a coarse native filter delivers nothing while at rest');
  });

  test('GPS jitter inside the radius does not end stillness; leaving it does', () {
    p.onFix(lat: 52.52, lng: 13.405);
    p.setForeground(false);
    tick(const Duration(seconds: 31));
    expect(p.profile, SendPolicy.backgroundStill);

    p.onFix(lat: 52.52005, lng: 13.405); // ~5.5 m north
    expect(p.profile, SendPolicy.backgroundStill);

    p.onFix(lat: 52.5202, lng: 13.405); // ~22 m north
    expect(p.profile, SendPolicy.backgroundMoving);
    tick(const Duration(seconds: 31));
    expect(p.profile, SendPolicy.backgroundStill, reason: 'a new anchor, resting again');
  });

  test('walking pace ends stillness even before the radius is crossed', () {
    p.onFix(lat: 52.52, lng: 13.405);
    p.setForeground(false);
    tick(const Duration(seconds: 31));
    expect(p.stationary, isTrue);
    p.onFix(lat: 52.52001, lng: 13.405, speed: 2.0);
    expect(p.stationary, isFalse);
    p.onFix(lat: 52.52001, lng: 13.405, speed: 0.4);
    expect(p.stationary, isFalse, reason: 'slow speed alone does not restart the clock');
  });

  test('coming back to the foreground is live immediately, going back keeps the rest state', () {
    p.onFix(lat: 52.52, lng: 13.405);
    p.setForeground(false);
    tick(const Duration(seconds: 40));
    expect(p.profile, SendPolicy.backgroundStill);
    p.setForeground(true);
    expect(p.profile, SendPolicy.foregroundProfile);
    p.setForeground(false);
    expect(p.profile, SendPolicy.backgroundStill, reason: 'still resting at the same spot');
  });

  test('reset forgets the anchor so the first fix after a restart sets it', () {
    p.onFix(lat: 52.52, lng: 13.405);
    tick(const Duration(minutes: 1));
    p.reset();
    p.setForeground(false);
    expect(p.stationary, isFalse);
    p.onFix(lat: 52.52, lng: 13.405);
    expect(p.stationary, isFalse);
    tick(const Duration(seconds: 30));
    expect(p.stationary, isTrue);
  });

  test('distance helper is close to the truth', () {
    // Berlin Alexanderplatz to Brandenburger Tor: about 2.2 km.
    final d = SendPolicy.distanceMeters(52.5219, 13.4132, 52.5163, 13.3777);
    expect(d, closeTo(2480, 60));
    expect(SendPolicy.distanceMeters(52.52, 13.405, 52.52, 13.405), 0);
  });
}
