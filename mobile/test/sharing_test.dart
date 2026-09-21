/// The sharing state machine.
///
/// One property matters more than everything else in this file: a position must
/// never leave the device after the user has stopped sharing. It is invisible
/// from the outside — nothing crashes, no log appears, the peer simply sees a
/// bee that should be gone — so it needs a test that would actually catch it.
///
/// A review found exactly that bug: `startSharing` set its "already sharing"
/// flag only after two awaited platform calls, so a double tap attached a second
/// fix subscription and heartbeat, and the stop path cancelled only the second
/// pair. These tests pin the behaviour that fix restored.
library;


import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:herebee/core/crypto.dart';
import 'package:herebee/core/net.dart';
import 'package:herebee/core/storage.dart';
import 'package:herebee/core/types.dart';
import 'package:herebee/features/room/room_controller.dart';
import 'package:herebee_location/herebee_location.dart';
import 'package:shared_preferences/shared_preferences.dart';

const String _secret = 'ByxRdpvA5QovVHmew-gNMld8ocbrEDVaf6TJ7hM4XYI';
const MethodChannel _methods = MethodChannel('app.herebee/location');
const String _eventChannel = 'app.herebee/location/updates';

/// Records what the app would have sent, and never touches a socket.
class RecordingNetClient extends NetClient {
  RecordingNetClient({required super.keys, required super.handlers})
      : super(endpoint: 'ws://test', cid: 'cid', clientLabel: 'test/1');

  final List<PeerUpdate> sent = [];
  bool closed = false;

  List<LocUpdate> get positions => sent.whereType<LocUpdate>().toList();
  List<StopUpdate> get stops => sent.whereType<StopUpdate>().toList();

  @override
  Future<void> connect() async {}

  @override
  Future<void> broadcast(PeerUpdate update) async => sent.add(update);

  @override
  void resync() {}

  @override
  Future<void> close() async => closed = true;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  late RecordingNetClient net;
  late List<String> platformCalls;
  late bool platformSharing;
  Object? startError;

  /// Push an event as the platform would.
  Future<void> emit(Map<Object?, Object?> event) async {
    await messenger.handlePlatformMessage(
      _eventChannel,
      const StandardMethodCodec().encodeSuccessEnvelope(event),
      (_) {},
    );
  }

  Future<void> emitFix({double lat = 52.52, double lng = 13.405}) => emit({
        'event': 'fix',
        'lat': lat,
        'lng': lng,
        'acc': 5.0,
        'hdg': null,
        'spd': null,
        'at': DateTime.now().millisecondsSinceEpoch,
      });

  Future<RoomController> makeController() async {
    SharedPreferences.setMockInitialValues({});
    final controller = RoomController(
      secret: _secret,
      storage: await Storage.open(),
      languageCode: 'en',
      youSuffix: '(you)',
      netClientFactory: ({
        required String endpoint,
        required RoomKeys keys,
        required String cid,
        required String clientLabel,
        required NetHandlers handlers,
      }) {
        net = RecordingNetClient(keys: keys, handlers: handlers);
        return net;
      },
    );
    await controller.init();
    await controller.enter();
    return controller;
  }

  Future<void> start(RoomController c) => c.startSharing(
        notificationTitle: 't',
        notificationBody: 'b',
        notificationStopLabel: 's',
      );

  setUp(() {
    platformCalls = [];
    platformSharing = false;
    startError = null;
    messenger.setMockMethodCallHandler(_methods, (call) async {
      platformCalls.add(call.method);
      switch (call.method) {
        case 'start':
          if (startError != null) throw startError!;
          platformSharing = true;
          return null;
        case 'stop':
          platformSharing = false;
          return null;
        case 'isSharing':
          return platformSharing;
        case 'isBatteryOptimized':
          return false;
        case 'checkPermission':
        case 'requestPermission':
          return 'whileInUse';
        default:
          return null;
      }
    });
    // The event channel's listen/cancel arrive as method calls on its own name.
    messenger.setMockMethodCallHandler(const MethodChannel(_eventChannel), (_) async => null);
  });

  tearDown(() {
    messenger.setMockMethodCallHandler(_methods, null);
    messenger.setMockMethodCallHandler(const MethodChannel(_eventChannel), null);
  });

  // Verified to fail against the pre-fix code: with `_toggling` and the
  // `!_sharing` guards removed, 'a double start…' and 'disposing while
  // sharing…' both fail. The single-start test below passes either way — it
  // pins the ordinary path, and it is the DOUBLE-start test that covers the
  // orphaned-subscription bug the review found.
  test('stopping cancels the platform subscription, so nothing follows the stop', () async {
    final c = await makeController();
    await start(c);
    await emitFix();
    await Future<void>.delayed(Duration.zero);
    expect(net.positions, hasLength(1), reason: 'the first fix goes out immediately');

    await c.stopSharing();
    expect(net.stops, hasLength(1), reason: 'peers must be told explicitly');

    // The platform stop is asynchronous on both platforms, so a straggler fix
    // after it is normal, not exotic.
    await emitFix(lat: 48.1, lng: 11.5);
    await Future<void>.delayed(Duration.zero);

    expect(net.positions, hasLength(1),
        reason: 'a position sent after the user stopped is the worst bug this app can have');
    expect(net.sent.last, isA<StopUpdate>(), reason: 'the stop must remain the last word');
    c.dispose();
  });

  test('a double start cannot orphan a subscription that outlives the stop', () async {
    final c = await makeController();
    // The bug this pins: both calls are in flight before either completes —
    // exactly what a double tap produces, because the platform round-trips take
    // milliseconds. Before the fix, the second call attached a second fix
    // subscription and heartbeat, and the stop cancelled only the second pair;
    // the first kept broadcasting a position every 10 seconds forever.
    await Future.wait([start(c), start(c)]);
    expect(platformCalls.where((m) => m == 'start'), hasLength(1),
        reason: 'the second tap must be refused, not queued');

    await emitFix();
    await Future<void>.delayed(Duration.zero);
    expect(net.positions, hasLength(1), reason: 'one fix must produce exactly one broadcast');

    await c.stopSharing();
    await emitFix(lat: 48.1, lng: 11.5);
    await Future<void>.delayed(Duration.zero);
    expect(net.positions, hasLength(1), reason: 'no orphaned subscription may survive the stop');
    c.dispose();
  });

  test('disposing while sharing stops the platform and tells peers', () async {
    final c = await makeController();
    await start(c);
    await emitFix();
    await Future<void>.delayed(Duration.zero);

    c.dispose();
    await Future<void>.delayed(Duration.zero);

    expect(platformCalls, contains('stop'),
        reason: 'a room switch must not leave GPS running with no UI that admits it');
    expect(net.stops, hasLength(1), reason: 'peers should see us go, not a 20-minute ghost');
  });

  test('a platform stop tears our side down and is reported once', () async {
    final c = await makeController();
    await start(c);
    await emitFix();
    await Future<void>.delayed(Duration.zero);

    await emit({'event': 'stopped', 'reason': 'permissionLost'});
    await Future<void>.delayed(Duration.zero);

    expect(c.sharing, isFalse);
    expect(c.stoppedReason, LocationStopReason.permissionLost);
    expect(net.stops, hasLength(1));

    await emitFix(lat: 48.1, lng: 11.5);
    await Future<void>.delayed(Duration.zero);
    expect(net.positions, hasLength(1));
    c.dispose();
  });

  test('a failed start leaves no listeners behind', () async {
    final c = await makeController();
    startError = PlatformException(code: 'servicesDisabled');
    await expectLater(start(c), throwsA(isA<LocationException>()));
    expect(c.sharing, isFalse);
    expect(c.toggling, isFalse, reason: 'the control must become usable again');

    await emitFix();
    await Future<void>.delayed(Duration.zero);
    expect(net.sent, isEmpty, reason: 'a session that never began must not broadcast');
    c.dispose();
  });

  test('resume ends sharing when the platform has quietly stopped', () async {
    final c = await makeController();
    await start(c);
    await emitFix();
    await Future<void>.delayed(Duration.zero);

    // The Android service can be killed by vendor power management without any
    // callback. Believing otherwise would keep the heartbeat re-broadcasting a
    // stale position with a fresh timestamp.
    platformSharing = false;
    c.resume();
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);

    expect(c.sharing, isFalse);
    expect(c.stoppedReason, LocationStopReason.killedBySystem);
    c.dispose();
  });

  test('our own marker is never aged out of the map while sharing', () async {
    final c = await makeController();
    await start(c);
    await emitFix();
    await Future<void>.delayed(Duration.zero);

    final self = c.peers[c.selfSeed!];
    expect(self, isNotNull);
    // Well past the linger window. Peers keep seeing us because of the
    // heartbeat, so removing our own bee would tell the user the opposite of
    // the truth.
    self!.at = DateTime.now().millisecondsSinceEpoch - const Duration(hours: 1).inMilliseconds;
    final removed = c.peers.tick(DateTime.now());
    expect(removed, isEmpty);
    expect(c.peers[c.selfSeed!], isNotNull);
    c.dispose();
  });
}
