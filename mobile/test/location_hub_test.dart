import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:herebee/core/location_hub.dart';
import 'package:herebee/core/send_policy.dart';
import 'package:herebee_location/herebee_location.dart';

class FakePlatform implements LocationPlatform {
  final List<String> calls = [];
  final List<LocationRequest> requests = [];
  final List<String> bodies = [];
  final StreamController<LocationFix> fixes = StreamController.broadcast();
  final StreamController<LocationStopReason> stopEvents = StreamController.broadcast();
  bool running = false;
  Object? startError;

  @override
  Stream<LocationFix> get updates => fixes.stream;

  @override
  Stream<LocationStopReason> get stops => stopEvents.stream;

  @override
  Future<void> start({
    required String notificationTitle,
    required String notificationBody,
    required String notificationStopLabel,
    required double distanceFilterMeters,
    required int intervalMs,
    required bool lowPower,
  }) async {
    calls.add('start');
    if (startError != null) throw startError!;
    running = true;
    bodies.add(notificationBody);
    requests.add((distanceFilterMeters: distanceFilterMeters, intervalMs: intervalMs, lowPower: lowPower));
  }

  @override
  Future<void> stop() async {
    calls.add('stop');
    running = false;
  }

  @override
  Future<void> reconfigure({
    required double distanceFilterMeters,
    required int intervalMs,
    required bool lowPower,
  }) async {
    calls.add('reconfigure');
    requests.add((distanceFilterMeters: distanceFilterMeters, intervalMs: intervalMs, lowPower: lowPower));
  }

  @override
  Future<void> updateNotification({required String notificationTitle, required String notificationBody}) async {
    calls.add('notify');
    bodies.add(notificationBody);
  }

  @override
  Future<bool> isSharing() async => running;
}

const SharingNotice notice = SharingNotice(title: 't', body: _body, stopLabel: 's');

String _body(int rooms) => rooms == 1 ? 'one room' : '$rooms rooms';

void main() {
  late FakePlatform platform;
  late LocationHub hub;
  final a = Object();
  final b = Object();

  setUp(() {
    platform = FakePlatform();
    hub = LocationHub(platform);
  });

  test('two rooms share one platform session, the last release stops it', () async {
    await hub.acquire(a, SendPolicy.foregroundProfile, notice);
    await hub.acquire(b, SendPolicy.foregroundProfile, notice);
    expect(platform.calls.where((c) => c == 'start'), hasLength(1));

    await hub.release(a);
    expect(platform.calls, isNot(contains('stop')));
    expect(platform.running, isTrue);

    await hub.release(b);
    expect(platform.calls.last, 'stop');
    expect(hub.holders, 0);
  });

  test('releasing a room that does not hold the session changes nothing', () async {
    await hub.acquire(a, SendPolicy.foregroundProfile, notice);
    await hub.release(b);
    expect(platform.calls, ['start']);
  });

  test('the platform gets the most demanding request of all rooms', () async {
    await hub.acquire(a, SendPolicy.backgroundStill, notice);
    expect(platform.requests.last, (distanceFilterMeters: 25.0, intervalMs: 15000, lowPower: true));

    await hub.acquire(b, SendPolicy.backgroundMoving, notice);
    expect(platform.requests.last, (distanceFilterMeters: 10.0, intervalMs: 3000, lowPower: false));

    await hub.update(b, SendPolicy.foregroundProfile);
    expect(platform.requests.last, (distanceFilterMeters: 3.0, intervalMs: 1000, lowPower: false));

    await hub.release(b);
    expect(platform.requests.last, (distanceFilterMeters: 25.0, intervalMs: 15000, lowPower: true));
  });

  test('an unchanged merged request is not sent again', () async {
    await hub.acquire(a, SendPolicy.foregroundProfile, notice);
    await hub.acquire(b, SendPolicy.backgroundMoving, notice);
    await hub.update(b, SendPolicy.backgroundStill);
    expect(platform.calls.where((c) => c == 'reconfigure'), isEmpty);
  });

  test('the notification counts the sharing rooms', () async {
    await hub.acquire(a, SendPolicy.foregroundProfile, notice);
    await hub.acquire(b, SendPolicy.foregroundProfile, notice);
    expect(platform.bodies, ['one room', '2 rooms']);
    await hub.release(b);
    expect(platform.bodies.last, 'one room');
  });

  test('a platform stop ends the session for every room', () async {
    final seen = <LocationStopReason>[];
    final sub = hub.stops.listen(seen.add);
    await hub.acquire(a, SendPolicy.foregroundProfile, notice);
    await hub.acquire(b, SendPolicy.foregroundProfile, notice);

    platform.stopEvents.add(LocationStopReason.permissionLost);
    await Future<void>.delayed(Duration.zero);
    expect(seen, [LocationStopReason.permissionLost]);
    expect(hub.holders, 0);

    await hub.acquire(a, SendPolicy.foregroundProfile, notice);
    expect(platform.calls.where((c) => c == 'start'), hasLength(2), reason: 'sharing again starts afresh');
    await sub.cancel();
  });

  test('a failed start holds nothing', () async {
    platform.startError = const LocationException('servicesDisabled', 'off');
    await expectLater(hub.acquire(a, SendPolicy.foregroundProfile, notice), throwsA(isA<LocationException>()));
    expect(hub.holders, 0);

    platform.startError = null;
    await hub.acquire(b, SendPolicy.foregroundProfile, notice);
    expect(hub.holds(b), isTrue);
  });

  test('concurrent acquire and release run in order', () async {
    await Future.wait([
      hub.acquire(a, SendPolicy.foregroundProfile, notice),
      hub.release(a),
      hub.acquire(b, SendPolicy.foregroundProfile, notice),
    ]);
    expect(platform.calls, ['start', 'stop', 'start']);
    expect(platform.running, isTrue);
  });
}
