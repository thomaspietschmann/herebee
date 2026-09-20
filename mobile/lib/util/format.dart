/// Formatting shared by the map and the sheets. Mirrors the helpers in
/// `client/src/main.ts` and `client/src/markers.ts` so both clients phrase
/// distances and ages identically.
library;

import 'dart:math' as math;

import '../l10n/app_localizations.dart';

/// Great-circle distance in metres between two points.
double distanceMeters(double lat1, double lng1, double lat2, double lng2) {
  const r = 6371000.0;
  double toRad(double d) => d * math.pi / 180;
  final dLat = toRad(lat2 - lat1);
  final dLng = toRad(lng2 - lng1);
  final s = math.pow(math.sin(dLat / 2), 2) +
      math.cos(toRad(lat1)) * math.cos(toRad(lat2)) * math.pow(math.sin(dLng / 2), 2);
  return 2 * r * math.asin(math.sqrt(s.toDouble()));
}

String formatDistance(double m) =>
    m < 1000 ? '${m.round()} m' : '${(m / 1000).toStringAsFixed(1)} km';

/// "just now" / "42 s ago" / "3 min ago", matching `relTime` in markers.ts.
String relTime(Duration age, L l) {
  final ms = age.inMilliseconds;
  if (ms < 5000) return l.justNow;
  if (ms < 60000) return l.secsAgo('${(ms / 1000).round()}');
  return l.minsAgo('${(ms / 60000).round()}');
}
