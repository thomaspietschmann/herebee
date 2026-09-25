/// Wire protocol between app and relay. Port of `shared/messages.ts` plus the
/// inbound validation in `client/src/net.ts`. See `shared/PROTOCOL.md`.
library;

import 'names.dart';
import 'types.dart';

const int roomIdLength = 32;
const int _seedMax = 128;

/// Frames the server can send. Anything unrecognised is ignored, not an error.
sealed class ServerMessage {
  const ServerMessage();

  static ServerMessage? parse(Object? decoded) {
    if (decoded is! Map) return null;
    switch (decoded['t']) {
      case 'hello':
        final id = decoded['selfId'];
        return id is String ? HelloMessage(id) : null;
      case 'peer':
        final id = decoded['id'];
        final data = decoded['data'];
        return id is String && data is String ? PeerMessage(id, data) : null;
      case 'request':
        return const RequestMessage();
      case 'left':
        final id = decoded['id'];
        return id is String ? LeftMessage(id) : null;
      case 'presence':
        final n = decoded['n'];
        return n is int ? PresenceMessage(n) : null;
      case 'pong':
        return const PongMessage();
      case 'error':
        final reason = decoded['reason'];
        return ErrorMessage(reason is String ? reason : 'unknown');
      default:
        return null;
    }
  }
}

class HelloMessage extends ServerMessage {
  const HelloMessage(this.selfId);
  final String selfId;
}

class PeerMessage extends ServerMessage {
  const PeerMessage(this.id, this.data);
  final String id;

  /// Opaque ciphertext. Decrypting it is the caller's job.
  final String data;
}

class RequestMessage extends ServerMessage {
  const RequestMessage();
}

class LeftMessage extends ServerMessage {
  const LeftMessage(this.id);
  final String id;
}

class PresenceMessage extends ServerMessage {
  const PresenceMessage(this.n);
  final int n;
}

class PongMessage extends ServerMessage {
  const PongMessage();
}

class ErrorMessage extends ServerMessage {
  const ErrorMessage(this.reason);
  final String reason;
}

Map<String, dynamic> joinFrame(String roomId, String cid) =>
    {'t': 'join', 'roomId': roomId, 'cid': cid};

Map<String, dynamic> relayFrame(String data) => {'t': 'relay', 'data': data};

const Map<String, dynamic> pingFrame = {'t': 'ping'};

/// Validate a DECRYPTED peer payload before it reaches the map.
///
/// Every room member holds the same key, so a malicious member can put arbitrary
/// plaintext inside a perfectly valid ciphertext. `seed` feeds map keys and the
/// avatar generator, and the coordinates drive the camera, so anything malformed
/// is dropped rather than rendered. Port of `validPeerUpdate` in
/// `client/src/net.ts`.
PeerUpdate? validPeerUpdate(Object? raw) {
  if (raw is! Map) return null;
  final seed = raw['seed'];
  if (seed is! String || seed.isEmpty || seed.length > _seedMax) return null;
  if (raw['k'] == 'stop') return StopUpdate(seed);
  if (raw['k'] != 'loc') return null;

  double? inRange(Object? v, double lo, double hi) {
    if (v is! num) return null;
    final d = v.toDouble();
    if (!d.isFinite || d < lo || d > hi) return null;
    return d;
  }

  final lat = inRange(raw['lat'], -90, 90);
  final lng = inRange(raw['lng'], -180, 180);
  if (lat == null || lng == null) return null;

  // Optional fields: null is allowed, a non-finite number is not.
  (double?, bool) optNum(Object? v) {
    if (v == null) return (null, true);
    if (v is num && v.toDouble().isFinite) return (v.toDouble(), true);
    return (null, false);
  }

  final (acc, accOk) = optNum(raw['acc']);
  final (hdg, hdgOk) = optNum(raw['hdg']);
  final (spd, spdOk) = optNum(raw['spd']);
  if (!accOk || !hdgOk || !spdOk) return null;

  final at = raw['at'];
  if (at is! num || !at.toDouble().isFinite) return null;

  return LocUpdate(
    seed: seed,
    lat: lat,
    lng: lng,
    acc: acc,
    hdg: hdg,
    spd: spd,
    at: at.toInt(),
    // A malformed name drops only the name, not the position.
    name: sanitizeSharedName(raw['name']),
  );
}
