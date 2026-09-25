/// How often to ask the platform for fixes and how often to send them,
/// depending on whether the app is on screen and whether the device moves.
///
/// Four states, two axes:
///
/// | state                  | native request      | send cap | heartbeat |
/// |------------------------|---------------------|----------|-----------|
/// | foreground, moving     | 1 s / 3 m           | 1 s      | 10 s      |
/// | foreground, stationary | 1 s / 3 m           | 1 s      | 10 s      |
/// | background, moving     | 3 s / 10 m          | 3 s      | 10 s      |
/// | background, stationary | 15 s / 25 m         | 3 s      | 30 s      |
///
/// The savings come from the native request more than from the send cap: GPS
/// at one fix per second is what drains the battery, a WebSocket frame is
/// cheap. The foreground keeps the live feel unchanged.
///
/// "Stationary" means no fix further than [stillRadius] from the anchor for
/// [stillAfter], the anchor being where we last came to rest. The radius is
/// well above GPS jitter so a phone on a table does not flap between states;
/// walking pace ([walkingSpeed]) ends stillness at once even before the radius
/// is crossed. Peers show a bee as live for 45 s (see peer_state.dart), so the
/// 30 s heartbeat never makes a resting sharer look offline.
///
/// Pure state machine so it can be unit-tested; the controller feeds it fixes,
/// lifecycle changes and clock ticks, and applies [profile] when it changes.
library;

import 'dart:math';

class SendProfile {
  const SendProfile({
    required this.distanceFilterMeters,
    required this.intervalMs,
    required this.minSend,
    required this.heartbeat,
  });

  /// Native request: deliver a fix only after moving this far ...
  final double distanceFilterMeters;

  /// ... and not more often than this (Android; iOS has no interval).
  final int intervalMs;

  /// Outbound cap between position updates.
  final Duration minSend;

  /// Re-send the last position this often while nothing new arrives.
  final Duration heartbeat;

  @override
  bool operator ==(Object other) =>
      other is SendProfile &&
      other.distanceFilterMeters == distanceFilterMeters &&
      other.intervalMs == intervalMs &&
      other.minSend == minSend &&
      other.heartbeat == heartbeat;

  @override
  int get hashCode => Object.hash(distanceFilterMeters, intervalMs, minSend, heartbeat);
}

class SendPolicy {
  SendPolicy({DateTime Function()? clock}) : _clock = clock ?? DateTime.now;

  static const SendProfile foregroundProfile = SendProfile(
    distanceFilterMeters: 3,
    intervalMs: 1000,
    minSend: Duration(seconds: 1),
    heartbeat: Duration(seconds: 10),
  );
  static const SendProfile backgroundMoving = SendProfile(
    distanceFilterMeters: 10,
    intervalMs: 3000,
    minSend: Duration(seconds: 3),
    heartbeat: Duration(seconds: 10),
  );
  static const SendProfile backgroundStill = SendProfile(
    distanceFilterMeters: 25,
    intervalMs: 15000,
    minSend: Duration(seconds: 3),
    heartbeat: Duration(seconds: 30),
  );

  static const double stillRadius = 10; // metres
  static const double walkingSpeed = 1.5; // m/s
  static const Duration stillAfter = Duration(seconds: 30);

  final DateTime Function() _clock;
  bool _foreground = true;
  double? _anchorLat, _anchorLng;
  DateTime? _anchorSince;

  bool get foreground => _foreground;

  /// True once the device has rested at the anchor for [stillAfter].
  bool get stationary {
    final since = _anchorSince;
    return since != null && _clock().difference(since) >= stillAfter;
  }

  SendProfile get profile {
    if (_foreground) return foregroundProfile;
    return stationary ? backgroundStill : backgroundMoving;
  }

  void setForeground(bool foreground) => _foreground = foreground;

  /// A new fix. Moves the anchor when the device left it or is walking.
  void onFix({required double lat, required double lng, double? speed}) {
    final aLat = _anchorLat, aLng = _anchorLng;
    final moved = aLat == null || aLng == null || distanceMeters(aLat, aLng, lat, lng) > stillRadius;
    final walking = speed != null && speed > walkingSpeed;
    if (moved || walking) {
      _anchorLat = lat;
      _anchorLng = lng;
      _anchorSince = _clock();
    }
  }

  /// Forget the anchor, e.g. when sharing starts: the first fix sets it.
  void reset() {
    _anchorLat = null;
    _anchorLng = null;
    _anchorSince = null;
  }

  /// Great-circle distance, good to well under a percent at these scales.
  static double distanceMeters(double lat1, double lng1, double lat2, double lng2) {
    const r = 6371000.0;
    final dLat = _rad(lat2 - lat1);
    final dLng = _rad(lng2 - lng1);
    final a = sin(dLat / 2) * sin(dLat / 2) +
        cos(_rad(lat1)) * cos(_rad(lat2)) * sin(dLng / 2) * sin(dLng / 2);
    return 2 * r * atan2(sqrt(a), sqrt(1 - a));
  }

  static double _rad(double deg) => deg * pi / 180;
}
