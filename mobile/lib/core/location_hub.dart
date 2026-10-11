import 'dart:async';

import 'package:herebee_location/herebee_location.dart';

import 'send_policy.dart';

abstract class LocationPlatform {
  Stream<LocationFix> get updates;
  Stream<LocationStopReason> get stops;

  Future<void> start({
    required String notificationTitle,
    required String notificationBody,
    required String notificationStopLabel,
    required double distanceFilterMeters,
    required int intervalMs,
    required bool lowPower,
  });

  Future<void> stop();

  Future<void> reconfigure({
    required double distanceFilterMeters,
    required int intervalMs,
    required bool lowPower,
  });

  Future<void> updateNotification({required String notificationTitle, required String notificationBody});

  Future<bool> isSharing();
}

class PluginLocationPlatform implements LocationPlatform {
  const PluginLocationPlatform();

  @override
  Stream<LocationFix> get updates => HereBeeLocation.updates;

  @override
  Stream<LocationStopReason> get stops => HereBeeLocation.stops;

  @override
  Future<void> start({
    required String notificationTitle,
    required String notificationBody,
    required String notificationStopLabel,
    required double distanceFilterMeters,
    required int intervalMs,
    required bool lowPower,
  }) =>
      HereBeeLocation.start(
        notificationTitle: notificationTitle,
        notificationBody: notificationBody,
        notificationStopLabel: notificationStopLabel,
        distanceFilterMeters: distanceFilterMeters,
        intervalMs: intervalMs,
        lowPower: lowPower,
      );

  @override
  Future<void> stop() => HereBeeLocation.stop();

  @override
  Future<void> reconfigure({
    required double distanceFilterMeters,
    required int intervalMs,
    required bool lowPower,
  }) =>
      HereBeeLocation.reconfigure(
        distanceFilterMeters: distanceFilterMeters,
        intervalMs: intervalMs,
        lowPower: lowPower,
      );

  @override
  Future<void> updateNotification({required String notificationTitle, required String notificationBody}) =>
      HereBeeLocation.updateNotification(notificationTitle: notificationTitle, notificationBody: notificationBody);

  @override
  Future<bool> isSharing() => HereBeeLocation.isSharing();
}

class SharingNotice {
  const SharingNotice({required this.title, required this.body, required this.stopLabel});

  final String title;
  final String Function(int rooms) body;
  final String stopLabel;
}

typedef LocationRequest = ({double distanceFilterMeters, int intervalMs, bool lowPower});

class LocationHub {
  LocationHub([this._platform = const PluginLocationPlatform()]);

  static final LocationHub instance = LocationHub();

  final LocationPlatform _platform;
  final Map<Object, SendProfile> _holders = {};
  LocationRequest? _applied;
  SharingNotice? _notice;
  Future<void> _queue = Future<void>.value();
  StreamSubscription<LocationStopReason>? _platformStops;
  StreamSubscription<LocationFix>? _platformFixes;
  LocationFix? _lastFix;

  LocationFix? get lastFix => _holders.isEmpty ? null : _lastFix;

  Stream<LocationFix> get fixes => _platform.updates;

  Stream<LocationStopReason> get stops {
    _watchStops();
    return _platform.stops;
  }

  void _watchStops() {
    _platformStops ??= _platform.stops.listen((_) {
      _holders.clear();
      _applied = null;
      _lastFix = null;
    });
    _platformFixes ??= _platform.updates.listen((fix) => _lastFix = fix);
  }

  int get holders => _holders.length;

  bool holds(Object holder) => _holders.containsKey(holder);

  Future<bool> isSharing() => _platform.isSharing();

  static LocationRequest merge(Iterable<SendProfile> profiles) {
    var distance = double.infinity;
    var interval = 1 << 30;
    var lowPower = true;
    for (final p in profiles) {
      if (p.distanceFilterMeters < distance) distance = p.distanceFilterMeters;
      if (p.intervalMs < interval) interval = p.intervalMs;
      lowPower = lowPower && p.lowPower;
    }
    return (distanceFilterMeters: distance, intervalMs: interval, lowPower: lowPower);
  }

  Future<T> _serial<T>(Future<T> Function() op) {
    final run = _queue.then((_) => op());
    _queue = run.then((_) {}, onError: (_) {});
    return run;
  }

  Future<void> acquire(Object holder, SendProfile profile, SharingNotice notice) => _serial(() async {
        _watchStops();
        if (_holders.containsKey(holder)) return;
        _notice = notice;
        if (_holders.isEmpty) {
          _lastFix = null;
          final request = merge([profile]);
          await _platform.start(
            notificationTitle: notice.title,
            notificationBody: notice.body(1),
            notificationStopLabel: notice.stopLabel,
            distanceFilterMeters: request.distanceFilterMeters,
            intervalMs: request.intervalMs,
            lowPower: request.lowPower,
          );
          _holders[holder] = profile;
          _applied = request;
          return;
        }
        _holders[holder] = profile;
        await _apply();
        await _announce();
      });

  Future<void> update(Object holder, SendProfile profile) => _serial(() async {
        if (!_holders.containsKey(holder)) return;
        _holders[holder] = profile;
        await _apply();
      });

  Future<void> release(Object holder) => _serial(() async {
        if (_holders.remove(holder) == null) return;
        if (_holders.isEmpty) {
          _applied = null;
          _lastFix = null;
          await _platform.stop();
          return;
        }
        await _apply();
        await _announce();
      });

  Future<void> _apply() async {
    final next = merge(_holders.values);
    if (next == _applied) return;
    _applied = next;
    await _platform.reconfigure(
      distanceFilterMeters: next.distanceFilterMeters,
      intervalMs: next.intervalMs,
      lowPower: next.lowPower,
    );
  }

  Future<void> _announce() async {
    final notice = _notice;
    if (notice == null) return;
    await _platform.updateNotification(
      notificationTitle: notice.title,
      notificationBody: notice.body(_holders.length),
    );
  }
}
