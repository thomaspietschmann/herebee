/// Location for HereBee, deliberately hand-written rather than taken off the
/// shelf.
///
/// The common Flutter location plugins pull in
/// `com.google.android.gms:play-services-location`. Keeping that out means the
/// app works on de-Googled phones and the "no third-party SDKs" claim on the
/// store listing is checkable. Android here uses the framework `LocationManager`
/// and iOS uses CoreLocation directly.
///
/// The native side deliberately does NOT touch the network. It hands raw fixes
/// to Dart, which encrypts them; no native code ever holds a coordinate in a
/// form it could transmit. See `shared/PROTOCOL.md`.
library;

import 'dart:async';

import 'package:flutter/services.dart';

const MethodChannel _methods = MethodChannel('app.herebee/location');
const EventChannel _events = EventChannel('app.herebee/location/updates');

/// A single position fix, in the units the wire protocol uses.
class LocationFix {
  const LocationFix({
    required this.lat,
    required this.lng,
    required this.at,
    this.acc,
    this.hdg,
    this.spd,
  });

  factory LocationFix.fromMap(Map<Object?, Object?> m) => LocationFix(
        lat: (m['lat']! as num).toDouble(),
        lng: (m['lng']! as num).toDouble(),
        at: (m['at']! as num).toInt(),
        acc: (m['acc'] as num?)?.toDouble(),
        hdg: (m['hdg'] as num?)?.toDouble(),
        spd: (m['spd'] as num?)?.toDouble(),
      );

  final double lat;
  final double lng;

  /// Accuracy in metres.
  final double? acc;

  /// Heading in degrees. Null unless the fix reports genuine movement.
  final double? hdg;

  /// Speed in m/s.
  final double? spd;

  /// Device clock at the fix, in milliseconds.
  final int at;
}

enum LocationPermissionState {
  /// Never asked.
  notDetermined,

  /// Granted for precise location while the app is in use. This is all HereBee
  /// asks for: on iOS the background mode covers a locked screen, and on Android
  /// the foreground service is started while the app is open.
  whileInUse,

  /// Granted, but only a coarse position (Android 12+ / iOS reduced accuracy).
  /// Usable, though the map will be visibly vague.
  coarseOnly,

  denied,

  /// Denied and the system will not ask again; only Settings can change it.
  deniedForever,

  /// Location is off device-wide.
  servicesDisabled,
}

/// Why sharing stopped without the user asking it to. Surfaced so a silent stop
/// never looks like "the others just cannot see me for some reason".
enum LocationStopReason { permissionLost, servicesDisabled, killedBySystem, stoppedFromNotification }

class LocationException implements Exception {
  const LocationException(this.code, this.message);
  final String code;
  final String message;

  @override
  String toString() => 'LocationException($code): $message';
}

class HereBeeLocation {
  const HereBeeLocation._();

  static Stream<Map<Object?, Object?>>? _raw;

  /// ONE subscription to the event channel, shared by every derived stream.
  ///
  /// Calling `receiveBroadcastStream()` twice opens two subscriptions to the
  /// same channel; the platform's second `onListen` replaces the first sink and
  /// the first stream silently goes dead. That looks exactly like location not
  /// working at all, with no error anywhere.
  static Stream<Map<Object?, Object?>> get _stream => _raw ??= _events
      .receiveBroadcastStream()
      .where((e) => e is Map)
      .map((e) => (e as Map).cast<Object?, Object?>())
      .asBroadcastStream();

  /// Position fixes while sharing is active.
  static Stream<LocationFix> get updates =>
      _stream.where((m) => m['event'] == 'fix').map(LocationFix.fromMap);

  /// Emitted when the platform stops sharing on its own.
  static Stream<LocationStopReason> get stops =>
      _stream.where((m) => m['event'] == 'stopped').map(
            (m) => LocationStopReason.values.firstWhere(
              (r) => r.name == m['reason'],
              orElse: () => LocationStopReason.killedBySystem,
            ),
          );

  static Future<LocationPermissionState> checkPermission() async {
    final name = await _methods.invokeMethod<String>('checkPermission');
    return LocationPermissionState.values.firstWhere(
      (s) => s.name == name,
      orElse: () => LocationPermissionState.denied,
    );
  }

  /// Ask for precise location while in use. Must be called from the foreground.
  static Future<LocationPermissionState> requestPermission() async {
    final name = await _methods.invokeMethod<String>('requestPermission');
    return LocationPermissionState.values.firstWhere(
      (s) => s.name == name,
      orElse: () => LocationPermissionState.denied,
    );
  }

  /// Begin sharing.
  ///
  /// Android starts a location-type foreground service with an ongoing
  /// notification; iOS enables background location updates. Both must be called
  /// while the app is in the foreground — neither platform allows starting this
  /// from the background, by design.
  ///
  /// [notificationTitle] / [notificationBody] / [notificationStopLabel] are the
  /// Android notification's text; they are passed in rather than hardcoded so
  /// they stay in the app's localisation.
  static Future<void> start({
    required String notificationTitle,
    required String notificationBody,
    required String notificationStopLabel,
    double distanceFilterMeters = 3,
    int intervalMs = 1000,
  }) async {
    try {
      await _methods.invokeMethod<void>('start', {
        'notificationTitle': notificationTitle,
        'notificationBody': notificationBody,
        'notificationStopLabel': notificationStopLabel,
        'distanceFilter': distanceFilterMeters,
        'intervalMs': intervalMs,
      });
    } on PlatformException catch (e) {
      throw LocationException(e.code, e.message ?? 'could not start location updates');
    }
  }

  static Future<void> stop() => _methods.invokeMethod<void>('stop');

  /// True while the platform is actively producing fixes.
  static Future<bool> isSharing() async =>
      await _methods.invokeMethod<bool>('isSharing') ?? false;

  /// Android only: whether this device's manufacturer is likely to kill the
  /// service anyway (see docs). False on iOS.
  static Future<bool> isBatteryOptimized() async =>
      await _methods.invokeMethod<bool>('isBatteryOptimized') ?? false;

  /// Android only: opens the system battery-optimisation settings so the user
  /// can exempt the app. Opening the screen needs no permission; HereBee
  /// deliberately does not request the exemption programmatically.
  static Future<void> openBatterySettings() =>
      _methods.invokeMethod<void>('openBatterySettings');

  /// Opens the app's settings page, for when permission was denied for good.
  static Future<void> openAppSettings() => _methods.invokeMethod<void>('openAppSettings');
}
