/// WebSocket client with auto-reconnect. Port of `client/src/net.ts`.
///
/// Encrypts every outbound update and decrypts inbound peer blobs. The socket
/// carries only opaque ciphertext plus the routing roomId; the AES key stays in
/// this process. Timings are fixed by `shared/PROTOCOL.md` — changing one here
/// alone makes this client and the browser time each other out inconsistently.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'crypto.dart';
import 'protocol.dart';
import 'types.dart';

const Duration _pingInterval = Duration(seconds: 15);
const Duration _staleLimit = Duration(seconds: 35);
const Duration _watchdogInterval = Duration(seconds: 5);
const Duration _resyncDebounce = Duration(seconds: 2);
const Duration _minBackoff = Duration(milliseconds: 500);
const Duration _maxBackoff = Duration(seconds: 15);

/// Sent on the upgrade so the relay can recognise a native client. The relay
/// treats the Origin check as browser CSRF hygiene, not authentication, and the
/// operator opts in by listing this value in ALLOWED_ORIGINS.
const String appOrigin = 'app://herebee';

class NetHandlers {
  const NetHandlers({
    required this.onPeer,
    required this.onLeft,
    required this.onRequest,
    required this.onStatus,
    required this.onPresence,
    required this.onFatal,
  });

  final void Function(String id, PeerUpdate update) onPeer;
  final void Function(String id) onLeft;

  /// A peer joined; re-broadcast our latest state.
  final void Function() onRequest;
  final void Function(bool connected) onStatus;

  /// Room occupancy (count only, no identity).
  final void Function(int n) onPresence;
  final void Function(String reason) onFatal;
}

class NetClient {
  NetClient({
    required this.endpoint,
    required this.keys,
    required this.cid,
    required this.clientLabel,
    required this.handlers,
  });

  /// e.g. wss://herebee.app/ws
  final String endpoint;
  final RoomKeys keys;
  final String cid;

  /// `<platform>/<version>`, sent as X-HereBee-Client.
  final String clientLabel;
  final NetHandlers handlers;

  WebSocket? _ws;
  StreamSubscription<dynamic>? _sub;
  Duration _backoff = _minBackoff;
  bool _closed = false;
  DateTime _lastResync = DateTime.fromMillisecondsSinceEpoch(0);

  /// The last "loc" frame, replayed on reconnect so peers see us again.
  String? _lastSent;
  DateTime _lastActivity = DateTime.fromMillisecondsSinceEpoch(0);
  Timer? _pingTimer;
  Timer? _watchdog;
  Timer? _reconnectTimer;

  Future<void> connect() async {
    if (_closed) return;
    // Always start from a clean slate: a previous socket may be dead but still
    // open (standby zombie), so a reconnect must never stack a second socket on
    // a live one.
    await _teardown();

    final WebSocket ws;
    try {
      ws = await WebSocket.connect(
        endpoint,
        headers: {'Origin': appOrigin, 'X-HereBee-Client': clientLabel},
      );
    } catch (_) {
      handlers.onStatus(false);
      _scheduleReconnect();
      return;
    }
    if (_closed) {
      await ws.close();
      return;
    }

    _ws = ws;
    _backoff = _minBackoff;
    _lastActivity = DateTime.now();
    _send(joinFrame(keys.roomId, cid));
    handlers.onStatus(true);
    if (_lastSent != null) ws.add(_lastSent!); // resume visibility after reconnect
    _startHeartbeat();

    _sub = ws.listen(
      _onFrame,
      onDone: _onDone,
      onError: (Object _) => _onDone(),
      cancelOnError: false,
    );
  }

  Future<void> _onFrame(dynamic raw) async {
    _lastActivity = DateTime.now(); // any inbound frame proves the link is alive
    if (raw is! String) return;
    Object? decoded;
    try {
      decoded = jsonDecode(raw);
    } catch (_) {
      return;
    }
    final msg = ServerMessage.parse(decoded);
    switch (msg) {
      case null:
      case HelloMessage():
      case PongMessage():
        return; // liveness / ack only — activity already recorded above
      case PeerMessage(:final id, :final data):
        final update = validPeerUpdate(await decryptJson(keys.key, data));
        if (update != null) handlers.onPeer(id, update);
      case LeftMessage(:final id):
        handlers.onLeft(id);
      case RequestMessage():
        handlers.onRequest();
      case PresenceMessage(:final n):
        handlers.onPresence(n);
      case ErrorMessage(:final reason):
        _closed = true;
        handlers.onFatal(reason);
    }
  }

  void _onDone() {
    _stopHeartbeat();
    handlers.onStatus(false);
    if (!_closed) _scheduleReconnect();
  }

  void _send(Map<String, dynamic> frame) => _ws?.add(jsonEncode(frame));

  Future<void> _teardown() async {
    _stopHeartbeat();
    final sub = _sub;
    final ws = _ws;
    _sub = null;
    _ws = null;
    await sub?.cancel();
    try {
      await ws?.close();
    } catch (_) {
      /* already gone */
    }
  }

  /// Application-level liveness. A dropped network can leave the socket wedged
  /// open, so `onDone` may never fire. Ping periodically and, if nothing arrives
  /// within the stale limit, rebuild the connection.
  void _startHeartbeat() {
    _stopHeartbeat();
    _lastActivity = DateTime.now();
    _pingTimer = Timer.periodic(_pingInterval, (_) => _send(pingFrame));
    _watchdog = Timer.periodic(_watchdogInterval, (_) {
      if (_ws == null) return;
      if (DateTime.now().difference(_lastActivity) <= _staleLimit) return;
      handlers.onStatus(false);
      unawaited(connect()); // tears down the zombie and reconnects
    });
  }

  void _stopHeartbeat() {
    _pingTimer?.cancel();
    _pingTimer = null;
    _watchdog?.cancel();
    _watchdog = null;
  }

  void _scheduleReconnect() {
    _reconnectTimer?.cancel();
    final delay = _backoff;
    _backoff = Duration(
      milliseconds: (_backoff.inMilliseconds * 2).clamp(0, _maxBackoff.inMilliseconds),
    );
    _reconnectTimer = Timer(delay, () {
      if (!_closed) unawaited(connect());
    });
  }

  /// Force a fresh connection. Call this when the app returns to the foreground:
  /// standby often leaves a socket that still reports open but carries nothing.
  void resync() {
    if (_closed) return;
    final now = DateTime.now();
    if (now.difference(_lastResync) < _resyncDebounce) return;
    _lastResync = now;
    _backoff = _minBackoff;
    unawaited(connect());
  }

  Future<void> broadcast(PeerUpdate update) async {
    final data = await encryptJson(keys.key, update.toJson());
    final frame = jsonEncode(relayFrame(data));
    // Replayed on every reconnect. A "stop" must clear it, or a later reconnect
    // would resurrect our old position and make us reappear after we stopped.
    if (update is LocUpdate) {
      _lastSent = frame;
    } else {
      _lastSent = null;
    }
    _ws?.add(frame);
  }

  Future<void> close() async {
    _closed = true;
    _reconnectTimer?.cancel();
    await _teardown();
  }
}
