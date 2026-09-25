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
import '../../core/send_policy.dart';
import '../../core/storage.dart';
import '../../core/types.dart';

/// State of the relay link. Named LinkState rather than ConnectionState so it
/// does not collide with Flutter's own type of that name.
enum LinkState { connecting, on, off }

/// Builds the relay client. Injectable so the sharing state machine can be
/// tested without a relay: whether a position is ever broadcast after the user
/// stopped is exactly the property that needs a test, and it is invisible from
/// the outside.
typedef NetClientFactory = NetClient Function({
  required String endpoint,
  required RoomKeys keys,
  required String cid,
  required String clientLabel,
  required NetHandlers handlers,
});

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
    this.onEntered,
    NetClientFactory? netClientFactory,
  }) : _newNetClient = netClientFactory ?? _defaultNetClient;

  /// Fired once, when the user actually enters the room. That, not merely
  /// opening a link, is what makes a room worth remembering.
  final VoidCallback? onEntered;

  static NetClient _defaultNetClient({
    required String endpoint,
    required RoomKeys keys,
    required String cid,
    required String clientLabel,
    required NetHandlers handlers,
  }) =>
      NetClient(
        endpoint: endpoint,
        keys: keys,
        cid: cid,
        clientLabel: clientLabel,
        handlers: handlers,
      );

  final NetClientFactory _newNetClient;

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

  /// True from the first await of a start/stop until it settles.
  ///
  /// `_sharing` alone is not enough: it can only be set AFTER the platform
  /// round-trips, so a second tap in that window would slip past it and attach a
  /// second fix subscription and heartbeat. The first pair would then outlive
  /// every stop and keep broadcasting a position after the user stopped, which
  /// is the one thing this app must never do.
  bool _toggling = false;
  bool get toggling => _toggling;

  /// Set in dispose(). Async work started before it must not touch this object
  /// afterwards: the socket handshake and the platform calls both outlive a
  /// room switch.
  bool _disposed = false;

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

  /// Outbound updates are capped (one per second in the foreground, matching
  /// the web client; less often in the background, see SendPolicy). Our own
  /// marker still moves with every fix; only what leaves the device is
  /// throttled.
  final SendPolicy _policy = SendPolicy();
  SendProfile _applied = SendPolicy.foregroundProfile;
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
    onEntered?.call();

    final net = _newNetClient(
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
    if (_disposed) {
      // A deep link switched rooms while the handshake was in flight. Without
      // this, the ticker below is attached to a dead controller and calls
      // notifyListeners() once a second forever.
      unawaited(net.close());
      return;
    }

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
  /// carries nothing. Rebuild it, and re-check what the platform is actually
  /// doing.
  void resume() {
    _net?.resync();
    unawaited(_reconcileSharing());
  }

  /// The Android service can die without telling us (vendor power management,
  /// low memory). Believing we still share would keep the heartbeat
  /// re-broadcasting a stale position with a fresh timestamp, so peers would
  /// watch a live bee standing at a place we left. Ask the platform instead.
  Future<void> _reconcileSharing() async {
    if (!_sharing || _toggling || _disposed) return;
    final actuallySharing = await HereBeeLocation.isSharing();
    if (actuallySharing || !_sharing || _disposed) return;
    _stoppedReason = LocationStopReason.killedBySystem;
    await _stopSharing(broadcastStop: true, callPlatform: false);
  }

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
    if (_sharing || _toggling || _disposed || _selfSeed == null) return;
    _toggling = true;
    _stoppedReason = null;
    notifyListeners();

    // Subscribe first: the platform can deliver a cached fix immediately, and a
    // listener attached afterwards would miss it. Cancel anything still attached
    // rather than overwriting it, so no subscription can be orphaned.
    await _fixSub?.cancel();
    await _stopSub?.cancel();
    _policy.reset();
    _applied = _policy.profile;
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
        distanceFilterMeters: _applied.distanceFilterMeters,
        intervalMs: _applied.intervalMs,
      );
    } catch (_) {
      // Do not leave listeners attached for a session that never began.
      await _fixSub?.cancel();
      await _stopSub?.cancel();
      _fixSub = null;
      _stopSub = null;
      _toggling = false;
      notifyListeners();
      rethrow;
    }

    if (_disposed) {
      // Disposed mid-start. The platform session is ours to clean up; nothing
      // else here may run.
      await HereBeeLocation.stop();
      await _fixSub?.cancel();
      await _stopSub?.cancel();
      return;
    }

    // Desktop-style static fixes and a stationary phone both mean the provider
    // may go quiet. Re-send the last position on a heartbeat so peers see us as
    // live and the relay's cached blob stays current for newcomers.
    _startHeartbeat();

    _batteryRisk = await HereBeeLocation.isBatteryOptimized();
    if (_disposed) return;
    _sharing = true;
    _toggling = false;
    notifyListeners();
  }

  /// The heartbeat also drives the policy clock: at rest in the background the
  /// coarse native filter delivers no fixes at all, so only time can move the
  /// policy from "moving" to "still".
  void _startHeartbeat() {
    _heartbeat?.cancel();
    _heartbeat = Timer.periodic(_applied.heartbeat, (_) {
      if (!_sharing || _lastPos == null) return;
      if (_applyPolicy()) return; // the change already flushed
      // Refresh our OWN last-seen too, not just the peers'. The web does this
      // (renderSelf before flushSend); without it a stationary sharer watches
      // their own bee decay to "no signal" and vanish after the linger window,
      // while everyone else still sees them live.
      _touchSelf();
      _flushSend();
    });
  }

  /// Re-stamp our own marker with the current time, without a new fix.
  void _touchSelf() {
    final seed = _selfSeed;
    final pos = _lastPos;
    if (seed == null || pos == null) return;
    peers.upsert(
      LocUpdate(
        seed: seed,
        lat: pos.lat,
        lng: pos.lng,
        acc: pos.acc,
        hdg: pos.hdg,
        spd: pos.spd,
        at: DateTime.now().millisecondsSinceEpoch,
      ),
      isSelf: true,
    );
  }

  /// Stop broadcasting. Peers see us disappear immediately.
  Future<void> stopSharing() => _stopSharing(broadcastStop: true, callPlatform: true);

  Future<void> _stopSharing({required bool broadcastStop, required bool callPlatform}) async {
    if (!_sharing) return;
    // Flip first: everything downstream (_onFix, _flushSend, the heartbeat)
    // checks this, so a fix still in flight from the platform cannot be
    // broadcast after the user stopped.
    _sharing = false;
    _toggling = true;
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
    _toggling = false;
    if (!_disposed) notifyListeners();
  }

  /// The screen reports lifecycle changes here. Coming back to the foreground
  /// restores the live cadence and sends at once, so the others never wait for
  /// a background timer to expire.
  void setForeground(bool foreground) {
    _policy.setForeground(foreground);
    _applyPolicy();
  }

  /// Apply the policy's current profile if it changed: reconfigure the
  /// platform request, restart the heartbeat at the new period, and send
  /// immediately so the transition itself is visible to peers. Returns whether
  /// anything changed.
  bool _applyPolicy() {
    final next = _policy.profile;
    if (next == _applied) return false;
    _applied = next;
    if (!_sharing) return true;
    unawaited(HereBeeLocation.reconfigure(
      distanceFilterMeters: next.distanceFilterMeters,
      intervalMs: next.intervalMs,
    ));
    _startHeartbeat();
    if (_lastPos != null) {
      _touchSelf();
      _flushSend();
    }
    return true;
  }

  void _onFix(LocationFix fix) {
    final seed = _selfSeed;
    // A fix can arrive after stop: the platform stop is asynchronous on both
    // sides, and a straggler must not resurrect us for our peers.
    if (seed == null || !_sharing || _disposed) return;
    _lastPos = Position(lat: fix.lat, lng: fix.lng, acc: fix.acc, hdg: fix.hdg, spd: fix.spd);
    _policy.onFix(lat: fix.lat, lng: fix.lng, speed: fix.spd);
    _applyPolicy();

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
    if (elapsed >= _applied.minSend) {
      _flushSend();
    } else {
      // A single trailing timer catches up with whatever the latest position is
      // by the time it fires, rather than queueing every fix.
      _pendingSend ??= Timer(_applied.minSend - elapsed, () {
        _pendingSend = null;
        _flushSend();
      });
    }
  }

  void _flushSend() {
    final pos = _lastPos;
    final seed = _selfSeed;
    if (pos == null || seed == null || !_sharing || _disposed) return;
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
    _disposed = true;
    _ageTimer?.cancel();
    _heartbeat?.cancel();
    _pendingSend?.cancel();
    unawaited(_fixSub?.cancel());
    unawaited(_stopSub?.cancel());
    _fixSub = null;
    _stopSub = null;

    // Leaving a room must end the platform's location session. Otherwise a room
    // switch while sharing leaves the foreground service and GPS running with
    // no UI that admits it, and on iOS no in-app way to stop at all.
    if (_sharing) {
      _sharing = false;
      final seed = _selfSeed;
      if (seed != null && _lastPos != null) {
        unawaited(_net!.broadcast(StopUpdate(seed)).whenComplete(() => _net?.close()));
      } else {
        unawaited(_net?.close());
      }
      unawaited(HereBeeLocation.stop());
    } else {
      unawaited(_net?.close());
    }
    unawaited(_panRequests.close());
    super.dispose();
  }
}
