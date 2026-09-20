/// Owns everything about one room: the socket, who is present, and what the map
/// should show. The widgets read it and never talk to the network themselves.
///
/// Port of the orchestration in `client/src/main.ts`, minus the multi-tab leader
/// election — a browser can have the same room open several times, an app
/// process cannot, so `coord.ts` has no counterpart here.
///
/// Phase 2 scope: the app joins as a WATCHER. It renders peers and counts as
/// present, but never broadcasts a position. Sharing arrives in Phase 3 with the
/// background location service; the "just watching" mode is a first-class state
/// in HereBee, not a stand-in.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';

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
  });

  final String secret;
  final Storage storage;

  /// Drives which nickname set is used, exactly as the browser's device locale
  /// does. Peers may therefore see different (but stable) names for each other.
  final String languageCode;

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
        // Nothing to re-broadcast while we are a watcher.
        onRequest: () {},
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

  int colorIndexFor(String seed) =>
      _colorIndex.putIfAbsent(seed, () => _colorIndex.length);

  String resolveName(String seed) =>
      storage.customName(seed) ?? nameFromSeed(seed, languageCode);

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
    unawaited(_net?.close());
    unawaited(_panRequests.close());
    super.dispose();
  }
}
