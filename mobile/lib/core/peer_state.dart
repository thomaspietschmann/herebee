/// Marker freshness and lifetime. Port of the state half of
/// `client/src/markers.ts`; the rendering half belongs to the map layer.
///
/// "Freshness" is expressed purely from the last-fix timestamp. Separately, a
/// peer can be flagged [offline] once its relay connection is KNOWN to have
/// dropped, which is different from merely not having sent a fix in a while —
/// without that flag a stationary-but-connected peer and a disconnected one look
/// identical.
///
/// A peer is removed only when it ACTIVELY stops sharing. If its signal is just
/// lost (app closed, tunnel, dead battery), the ghost lingers at its last known
/// spot for [lingerFor] and then disappears on its own.
library;

import 'dart:math';

import 'types.dart';

// 45 s, not 15: a sharer resting in the background sends only every 30 s
// (see send_policy.dart), and one missed heartbeat must not read as "no signal".
// Keep in sync with FRESH_MS in client/src/markers.ts.
const Duration freshFor = Duration(seconds: 45);
const Duration staleFor = Duration(minutes: 2);
const Duration lingerFor = Duration(minutes: 20);
const Duration maxClockSkew = Duration(seconds: 5);
const Duration messageFor = Duration(minutes: 10);

/// GPS heading is noise at low speed (it swings wildly while standing still), so
/// the arrow only shows once the fix reports genuine movement. ~1.5 m/s is a
/// slow walk, comfortably above GPS jitter.
const double minArrowSpeedMs = 1.5;

enum Tier { fresh, stale, ghost }

Tier tierOf(Duration age) {
  if (age >= staleFor) return Tier.ghost;
  if (age >= freshFor) return Tier.stale;
  return Tier.fresh;
}

class PeerEntry {
  PeerEntry({
    required this.seed,
    required this.position,
    required this.at,
    this.isSelf = false,
    this.offline = false,
  });

  final String seed;
  Position position;

  /// Client timestamp (ms) of the last fix.
  int at;
  bool isSelf;

  /// True once we know this peer's relay connection actually dropped. Cleared
  /// the moment a fresh "loc" arrives, which can only happen over a live link.
  bool offline;

  /// The name this peer chose to share, from its latest update. In memory
  /// only: it is theirs to show while they share, not ours to keep.
  String? sharedName;

  String? message;
  int? messageAt;
  int? messageLocalAt;

  void clearMessage() {
    message = null;
    messageAt = null;
    messageLocalAt = null;
  }

  bool applyMessage(String? msg, int? msgAt, {required int at, required int nowMs}) {
    if (msg == null || msgAt == null) {
      clearMessage();
      return false;
    }
    final age = max(0, at - msgAt);
    if (age >= messageFor.inMilliseconds) {
      clearMessage();
      return false;
    }
    final previous = messageAt;
    if (previous != null && msgAt < previous) return false;
    final fresh = previous == null || msgAt > previous;
    if (!fresh && message == msg) return false;
    message = msg;
    messageAt = msgAt;
    messageLocalAt = nowMs - age;
    return fresh;
  }

  Duration? messageAgeAt(DateTime now) {
    final local = messageLocalAt;
    return local == null ? null : Duration(milliseconds: now.millisecondsSinceEpoch - local);
  }

  Duration ageAt(DateTime now) =>
      Duration(milliseconds: now.millisecondsSinceEpoch - at);

  Tier tierAt(DateTime now) => tierOf(ageAt(now));

  bool showsHeading() {
    final spd = position.spd;
    return position.hdg != null && spd != null && spd >= minArrowSpeedMs;
  }
}

/// Holds every peer currently on the map, keyed by identity seed (stable across
/// reconnects, so a dropped and restored link updates the same marker instead of
/// spawning a duplicate).
class PeerStore {
  final Map<String, PeerEntry> _entries = {};

  Iterable<PeerEntry> get entries => _entries.values;
  PeerEntry? operator [](String seed) => _entries[seed];
  int get length => _entries.length;

  bool upsert(PeerUpdate update, {bool isSelf = false, DateTime? now}) {
    switch (update) {
      case StopUpdate():
        _entries.remove(update.seed); // active stop -> disappear now
        return false;
      case LocUpdate(
          :final seed,
          :final lat,
          :final lng,
          :final acc,
          :final hdg,
          :final spd,
          at: final sentAt,
          :final name,
          :final msg,
          :final msgAt
        ):
        final nowMs = (now ?? DateTime.now()).millisecondsSinceEpoch;
        if (sentAt < nowMs - lingerFor.inMilliseconds) return false;
        final at = min(sentAt, nowMs + maxClockSkew.inMilliseconds);
        final position = Position(lat: lat, lng: lng, acc: acc, hdg: hdg, spd: spd);
        final existing = _entries[seed];
        if (existing == null) {
          final entry = PeerEntry(seed: seed, position: position, at: at, isSelf: isSelf)..sharedName = name;
          _entries[seed] = entry;
          return entry.applyMessage(msg, msgAt, at: sentAt, nowMs: nowMs);
        } else {
          // Every update carries the name or not, so a peer who stops sharing
          // theirs falls back to the generated one with their next position.
          existing.sharedName = name;
          existing.position = position;
          existing.at = at;
          existing.isSelf = isSelf || existing.isSelf;
          existing.offline = false; // fresh data => the link is fine again
          return existing.applyMessage(msg, msgAt, at: sentAt, nowMs: nowMs);
        }
    }
  }

  void setOffline(String seed, bool offline) {
    final entry = _entries[seed];
    if (entry != null) entry.offline = offline;
  }

  void remove(String seed) => _entries.remove(seed);

  /// Drop ghosts whose last fix is older than [lingerFor]. Returns the seeds
  /// removed so callers can clean up markers and follow state.
  ///
  /// Our own marker is never dropped. It is owned by the sharing state, not by
  /// freshness: removing it would tell the user they had vanished at the very
  /// moment their peers still see them, which is the opposite of the truth.
  List<String> tick(DateTime now) {
    final expired = _entries.values
        .where((e) => !e.isSelf && e.ageAt(now) > lingerFor)
        .map((e) => e.seed)
        .toList();
    for (final seed in expired) {
      _entries.remove(seed);
    }
    final nowMs = now.millisecondsSinceEpoch;
    for (final e in _entries.values) {
      final local = e.messageLocalAt;
      if (local != null && nowMs - local >= messageFor.inMilliseconds) e.clearMessage();
    }
    return expired;
  }
}
