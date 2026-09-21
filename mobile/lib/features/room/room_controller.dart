/// Owns everything about one room: the socket, who is present, and what the map
/// should show. The widgets read it and never talk to the network themselves.
///
/// Port of the orchestration in `client/src/main.ts`, minus the multi-tab leader
/// election — a browser can have the same room open several times, an app
/// process cannot, so `coord.ts` has no counterpart here.
///
/// Watching and sharing are both first-class: a participant who never shares a
/// position is a normal member of the room, counted but anonymous.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:herebee_location/herebee_location.dart';

import '../../app_config.dart';
import '../../core/avatar.dart';
import '../../core/crypto.dart';
import '../../core/names.dart';
import '../../core/net.dart';
import '../../core/peer_state.dart';
import '../../core/storage.dart';
import '../../core/types.dart';

/// State of the relay link. Named LinkState rather than ConnectionState so it
/// does not collide with Flutter's own type of that name.
enum LinkState { connecting, on, off }

/// One row in the roster / one bee on the map.
class RosterEntry {
  const RosterEntry({
    required this.seed,
    required this.identity,
    required this.entry,
  });

  final String seed;
  final Identity identity;
  final PeerEntry entry;

  bool get offline => entry.offline;
}

class RoomController extends ChangeNotifier {
  RoomController({
    required this.secret,
    required this.storage,
    required this.languageCode,
    required this.youSuffix,
  });

  final String secret;
  final Storage storage;

  /// Drives which nickname set is used, exactly as the browser's device locale
  /// does. Peers may therefore see different (but stable) names for each other.
  final String languageCode;

  /// Localized "(you)". Appended to our own bee so you can spot yourself among
  /// a dozen identical-looking markers.
  final String youSuffix;

  RoomKeys? _keys;
  NetClient? _net;
  Timer? _ageTimer;

  final PeerStore peers = PeerStore();

  /// Relay socket id -> identity seed, so a `left` frame can be resolved back to
  /// a marker. A reconnect gets a new socket id, so this is rebuilt from the
  /// next update rather than persisted.
  final Map<String, String> _connSeed = {};

  /// Hue assigned by first-seen order, not by a seed hash, so people present at
  /// the same time stay visually distinct. Each device assigns independently.
  final Map<String, int> _colorIndex = {};

  String? _selfSeed;
  String? get selfSeed => _selfSeed;

  bool _entered = false;
  bool get entered => _entered;

  bool _invalidLink = false;
  bool get invalidLink => _invalidLink;

  LinkState _connection = LinkState.connecting;
  LinkState get connection => _connection;

  int _presence = 0;

  /// Everyone in the room, including watchers who never share a position.
  int get presence => _presence;

  String? _fatal;
  String? get fatal => _fatal;

  String? _followSeed;
  String? get followSeed => _followSeed;

  // --- sharing ------------------------------------------------------------
  StreamSubscription<LocationFix>? _fixSub;
  StreamSubscription<LocationStopReason>? _stopSub;
  Timer? _heartbeat;

  bool _sharing = false;
  bool get sharing => _sharing;

  /// Our own last fix, or null when not sharing.
  Position? _lastPos;
  Position? get lastPos => _lastPos;

  /// Set when the platform ended sharing on its own, so the UI can say why
  /// instead of just going quiet.
  LocationStopReason? _stoppedReason;
  LocationStopReason? get stoppedReason => _stoppedReason;

  /// Android: this device's vendor is likely to kill background services.
  bool _batteryRisk = false;
  bool get batteryRisk => _batteryRisk;

  /// Outbound updates are capped at one per second, matching the web client.
  /// Our own marker still moves with every fix; only what leaves the device is
  /// throttled.
  static const Duration _minSendInterval = Duration(seconds: 1);
  static const Duration _stationaryHeartbeat = Duration(seconds: 10);
  DateTime _lastSendAt = DateTime.fromMillisecondsSinceEpoch(0);
  Timer? _pendingSend;

  /// Emits a seed whose marker the camera should pan to. The screen listens;
  /// keeping the camera out of the controller keeps this testable.
  final StreamController<String> _panRequests = StreamController<String>.broadcast();
  Stream<String> get panRequests => _panRequests.stream;

  String get roomLink => AppConfig.roomLink(secret);
  String? get roomId => _keys?.roomId;

  Future<void> init() async {
    try {
      _keys = await deriveRoomKeys(secret);
      if (!await isValidRoomId(_keys!.roomId)) throw const FormatException('bad room id');
    } catch (_) {
      // A hand-edited or truncated link. Say so instead of joining a room nobody
      // else can reach.
      _invalidLink = true;
      notifyListeners();
      return;
    }
    _selfSeed = await storage.seed();
    notifyListeners();
  }

  /// Nothing touches the network until the user actively enters: becoming
  /// present is a deliberate act, and presence is visible to the room.
  Future<void> enter() async {
    if (_entered || _invalidLink) return;
    // Callers must await init() first; the screen guarantees it. Assert rather
    // than return quietly, because a silent no-op here looks exactly like a room
    // nobody else has joined.
    assert(_keys != null, 'enter() called before init() completed');
    if (_keys == null) return;
    _entered = true;
    notifyListeners();

    final net = NetClient(
      endpoint: AppConfig.wsUrl,
      keys: _keys!,
      cid: await storage.cid(),
      clientLabel: '${defaultTargetPlatform.name}/${AppConfig.clientVersion}',
      handlers: NetHandlers(
        onPeer: _onPeer,
        onLeft: _onLeft,
        onRequest: () {
          if (_sharing && _lastPos != null) _flushSend();
        },
        onStatus: (connected) {
          _connection = connected ? LinkState.on : LinkState.off;
          notifyListeners();
        },
        onPresence: (n) {
          _presence = n;
          notifyListeners();
        },
        onFatal: (reason) {
          _connection = LinkState.off;
          _fatal = reason;
          notifyListeners();
        },
      ),
    );
    _net = net;
    await net.connect();

    // Age markers once a second: freshness tiers change with time alone, and
    // ghosts past the linger window drop off on their own.
    _ageTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      final removed = peers.tick(DateTime.now());
      if (removed.contains(_followSeed)) _followSeed = null;
      notifyListeners(); // also refreshes "last seen" in an open info box
    });
  }

  void _onPeer(String id, PeerUpdate update) {
    // Ignore replays of our own identity: the relay replays each peer's last
    // cached blob on join, so a lingering previous socket could feed us back to
    // ourselves. (Only reachable once this client shares, in Phase 3.)
    if (update.seed == _selfSeed) return;
    _connSeed[id] = update.seed;
    peers.upsert(update);
    if (update is StopUpdate && _followSeed == update.seed) _followSeed = null;
    if (_followSeed == update.seed) _panRequests.add(update.seed);
    notifyListeners();
  }

  void _onLeft(String id) {
    final seed = _connSeed[id];
    if (seed == null) return;
    // Don't remove the marker: a dropped link is not the same as "stopped
    // sharing". It lingers as a ghost and says so.
    peers.setOffline(seed, true);
    notifyListeners();
  }

  /// Returning from the background can leave a socket that reports open but
  /// carries nothing. Rebuild it.
  void resume() => _net?.resync();

  // --- sharing ------------------------------------------------------------

  /// Ask the platform for permission. Must be called from the foreground.
  Future<LocationPermissionState> requestLocationPermission() =>
      HereBeeLocation.requestPermission();

  /// Start broadcasting our position.
  ///
  /// The caller supplies the notification text so it stays in the app's
  /// localisation rather than being hardcoded in the plugin. Throws
  /// [LocationException] if the platform refuses.
  Future<void> startSharing({
    required String notificationTitle,
    required String notificationBody,
    required String notificationStopLabel,
  }) async {
    if (_sharing || _selfSeed == null) return;
    _stoppedReason = null;

    // Subscribe first: the platform can deliver a cached fix immediately, and a
    // listener attached afterwards would miss it.
    _fixSub = HereBeeLocation.updates.listen(_onFix);
    _stopSub = HereBeeLocation.stops.listen((reason) {
      // The platform pulled the plug: permission revoked, location switched
      // off, or the service was killed. Tear down our side and say so.
      _stoppedReason = reason;
      unawaited(_stopSharing(broadcastStop: true, callPlatform: false));
    });

    try {
      await HereBeeLocation.start(
        notificationTitle: notificationTitle,
        notificationBody: notificationBody,
        notificationStopLabel: notificationStopLabel,
      );
    } catch (_) {
      // Do not leave listeners attached for a session that never began.
      await _fixSub?.cancel();
      await _stopSub?.cancel();
      _fixSub = null;
      _stopSub = null;
      rethrow;
    }

    // Desktop-style static fixes and a stationary phone both mean the provider
    // may go quiet. Re-send the last position on a heartbeat so peers see us as
    // live and the relay's cached blob stays current for newcomers.
    _heartbeat = Timer.periodic(_stationaryHeartbeat, (_) {
      if (_lastPos != null) _flushSend();
    });

    _batteryRisk = await HereBeeLocation.isBatteryOptimized();
    _sharing = true;
    unawaited(storage.setWasSharing(_keys!.roomId, true));
    notifyListeners();
  }

  /// Stop broadcasting. Peers see us disappear immediately.
  Future<void> stopSharing() => _stopSharing(broadcastStop: true, callPlatform: true);

  Future<void> _stopSharing({required bool broadcastStop, required bool callPlatform}) async {
    if (!_sharing) return;
    _sharing = false;
    await _fixSub?.cancel();
    await _stopSub?.cancel();
    _fixSub = null;
    _stopSub = null;
    _heartbeat?.cancel();
    _heartbeat = null;
    _pendingSend?.cancel();
    _pendingSend = null;
    if (callPlatform) await HereBeeLocation.stop();

    // An explicit stop is the ONLY thing that removes our marker on the other
    // side. Losing signal leaves a ghost; stopping must not.
    if (broadcastStop && _lastPos != null && _selfSeed != null) {
      await _net?.broadcast(StopUpdate(_selfSeed!));
    }
    _lastPos = null;
    peers.remove(_selfSeed ?? '');
    if (_keys != null) await storage.setWasSharing(_keys!.roomId, false);
    notifyListeners();
  }

  void _onFix(LocationFix fix) {
    final seed = _selfSeed;
    if (seed == null) return;
    _lastPos = Position(lat: fix.lat, lng: fix.lng, acc: fix.acc, hdg: fix.hdg, spd: fix.spd);

    // Render our own marker from every fix, unthrottled: the throttle exists to
    // spare the network, not to make our own dot stutter.
    peers.upsert(
      LocUpdate(
        seed: seed,
        lat: fix.lat,
        lng: fix.lng,
        acc: fix.acc,
        hdg: fix.hdg,
        spd: fix.spd,
        at: fix.at,
      ),
      isSelf: true,
    );
    if (_followSeed == seed) _panRequests.add(seed);
    notifyListeners();
    _scheduleSend();
  }

  void _scheduleSend() {
    final elapsed = DateTime.now().difference(_lastSendAt);
    if (elapsed >= _minSendInterval) {
      _flushSend();
    } else {
      // A single trailing timer catches up with whatever the latest position is
      // by the time it fires, rather than queueing every fix.
      _pendingSend ??= Timer(_minSendInterval - elapsed, () {
        _pendingSend = null;
        _flushSend();
      });
    }
  }

  void _flushSend() {
    final pos = _lastPos;
    final seed = _selfSeed;
    if (pos == null || seed == null) return;
    _lastSendAt = DateTime.now();
    unawaited(_net?.broadcast(LocUpdate(
      seed: seed,
      lat: pos.lat,
      lng: pos.lng,
      acc: pos.acc,
      hdg: pos.hdg,
      spd: pos.spd,
      at: DateTime.now().millisecondsSinceEpoch,
    )));
  }

  Future<void> openBatterySettings() => HereBeeLocation.openBatterySettings();

  Future<void> openAppSettings() => HereBeeLocation.openAppSettings();

  int colorIndexFor(String seed) =>
      _colorIndex.putIfAbsent(seed, () => _colorIndex.length);

  String resolveName(String seed) {
    final name = storage.customName(seed) ?? nameFromSeed(seed, languageCode);
    return seed == _selfSeed ? '$name $youSuffix' : name;
  }

  Identity identityFor(String seed) =>
      identityFromSeed(seed, resolveName(seed), hueFromIndex(colorIndexFor(seed)));

  Future<void> rename(String seed, String? name) async {
    await storage.setCustomName(seed, name);
    notifyListeners();
  }

  /// Sharers currently on the map, online first then alphabetical — the same
  /// ordering the web roster uses.
  List<RosterEntry> roster() {
    final list = peers.entries
        .map((e) => RosterEntry(seed: e.seed, identity: identityFor(e.seed), entry: e))
        .toList()
      ..sort((a, b) {
        final byOffline = (a.offline ? 1 : 0) - (b.offline ? 1 : 0);
        return byOffline != 0 ? byOffline : a.identity.name.compareTo(b.identity.name);
      });
    return list;
  }

  int get onlineSharers => peers.entries.where((e) => !e.offline).length;
  int get offlineSharers => peers.entries.where((e) => e.offline).length;

  /// Present but not sharing a position. Derived from the ONLINE sharers only,
  /// or the headline count and the number of bees on the map would disagree.
  int get watchers {
    final w = _presence - onlineSharers;
    return w < 0 ? 0 : w;
  }

  void toggleFollow(String seed) {
    _followSeed = _followSeed == seed ? null : seed;
    if (_followSeed != null) _panRequests.add(seed);
    notifyListeners();
  }

  /// The user took the camera over; stop following.
  void dropFollow() {
    if (_followSeed == null) return;
    _followSeed = null;
    notifyListeners();
  }

  @override
  void dispose() {
    _ageTimer?.cancel();
    _heartbeat?.cancel();
    _pendingSend?.cancel();
    unawaited(_fixSub?.cancel());
    unawaited(_stopSub?.cancel());
    unawaited(_net?.close());
    unawaited(_panRequests.close());
    super.dispose();
  }
}
