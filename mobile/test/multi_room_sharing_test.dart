import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:herebee/core/crypto.dart';
import 'package:herebee/core/location_hub.dart';
import 'package:herebee/core/net.dart';
import 'package:herebee/core/storage.dart';
import 'package:herebee/core/types.dart';
import 'package:herebee/features/room/room_controller.dart';
import 'package:herebee_location/herebee_location.dart';
import 'package:shared_preferences/shared_preferences.dart';

class RecordingNetClient extends NetClient {
  RecordingNetClient({required super.keys, required super.handlers})
      : super(endpoint: 'ws://test', cid: 'cid', clientLabel: 'test/1');

  final List<PeerUpdate> sent = [];

  List<LocUpdate> get positions => sent.whereType<LocUpdate>().toList();
  List<StopUpdate> get stops => sent.whereType<StopUpdate>().toList();

  @override
  Future<void> connect() async {}

  @override
  Future<void> broadcast(PeerUpdate update) async => sent.add(update);

  @override
  void resync() {}

  @override
  Future<void> close() async {}
}

class FakePlatform implements LocationPlatform {
  final StreamController<LocationFix> fixes = StreamController.broadcast(sync: true);
  final StreamController<LocationStopReason> stopEvents = StreamController.broadcast(sync: true);
  final List<String> calls = [];
  bool running = false;

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
    running = true;
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
  }) async {}

  @override
  Future<void> updateNotification({required String notificationTitle, required String notificationBody}) async {}

  @override
  Future<bool> isSharing() async => running;

  void fix({double lat = 52.52, double lng = 13.405}) => fixes.add(LocationFix(
        lat: lat,
        lng: lng,
        acc: 5,
        at: DateTime.now().millisecondsSinceEpoch,
      ));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  const methods = MethodChannel('app.herebee/location');

  late FakePlatform platform;
  late LocationHub hub;
  late Storage storage;
  final nets = <String, RecordingNetClient>{};

  Future<RoomController> room() async {
    final secret = generateSecret();
    final c = RoomController(
      secret: secret,
      storage: storage,
      languageCode: 'en',
      youSuffix: '(you)',
      locationHub: hub,
      netClientFactory: ({
        required String endpoint,
        required RoomKeys keys,
        required String cid,
        required String clientLabel,
        required NetHandlers handlers,
      }) =>
          nets[secret] = RecordingNetClient(keys: keys, handlers: handlers),
    );
    await c.init();
    await c.enter();
    return c;
  }

  Future<void> share(RoomController c) => c.startSharing(
        notificationTitle: 't',
        notificationBody: 'b',
        notificationStopLabel: 's',
      );

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    storage = await Storage.open();
    platform = FakePlatform();
    hub = LocationHub(platform);
    nets.clear();
    messenger.setMockMethodCallHandler(methods, (call) async => false);
  });

  tearDown(() => messenger.setMockMethodCallHandler(methods, null));

  test('a room that starts sharing later is seeded with the current position', () async {
    final a = await room();
    final b = await room();
    await share(a);
    platform.fix();
    await Future<void>.delayed(Duration.zero);
    expect(nets[a.secret]!.positions, hasLength(1));

    await share(b);
    await Future<void>.delayed(Duration.zero);
    expect(platform.calls.where((c) => c == 'start'), hasLength(1));
    expect(nets[b.secret]!.positions, hasLength(1),
        reason: 'a resting phone delivers no new fix, so B must not wait for one');
    expect(b.peers[b.selfSeed!], isNotNull, reason: 'B shows our own bee at once');
    a.dispose();
    b.dispose();
  });

  test('both rooms receive every fix, and stopping one leaves the other sharing', () async {
    final a = await room();
    final b = await room();
    await share(a);
    await share(b);
    platform.fix();
    await Future<void>.delayed(Duration.zero);
    expect(nets[a.secret]!.positions, hasLength(1));
    expect(nets[b.secret]!.positions, hasLength(1));

    await a.stopSharing();
    expect(nets[a.secret]!.stops, hasLength(1));
    expect(platform.running, isTrue, reason: 'B still shares');

    await Future<void>.delayed(const Duration(milliseconds: 1100));
    platform.fix(lat: 52.53);
    await Future<void>.delayed(Duration.zero);
    expect(nets[a.secret]!.positions, hasLength(1), reason: 'nothing leaves A after its stop');
    expect(nets[b.secret]!.positions, hasLength(2));

    b.dispose();
    await Future<void>.delayed(Duration.zero);
    expect(platform.running, isFalse);
    a.dispose();
  });

  test('a platform stop ends sharing in every room', () async {
    final a = await room();
    final b = await room();
    await share(a);
    await share(b);
    platform.fix();
    await Future<void>.delayed(Duration.zero);

    platform.stopEvents.add(LocationStopReason.stoppedFromNotification);
    await Future<void>.delayed(Duration.zero);
    expect(a.sharing, isFalse);
    expect(b.sharing, isFalse);
    expect(nets[a.secret]!.stops, hasLength(1));
    expect(nets[b.secret]!.stops, hasLength(1));
    a.dispose();
    b.dispose();
  });
}
