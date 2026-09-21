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

import 'types.dart';

const Duration freshFor = Duration(seconds: 15);
const Duration staleFor = Duration(minutes: 2);
const Duration lingerFor = Duration(minutes: 20);

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

  void upsert(PeerUpdate update, {bool isSelf = false}) {
    switch (update) {
      case StopUpdate():
        _entries.remove(update.seed); // active stop -> disappear now
      case LocUpdate(
          :final seed,
          :final lat,
          :final lng,
          :final acc,
          :final hdg,
          :final spd,
          :final at
        ):
        final position = Position(lat: lat, lng: lng, acc: acc, hdg: hdg, spd: spd);
        final existing = _entries[seed];
        if (existing == null) {
          _entries[seed] = PeerEntry(seed: seed, position: position, at: at, isSelf: isSelf);
        } else {
          existing.position = position;
          existing.at = at;
          existing.isSelf = isSelf || existing.isSelf;
          existing.offline = false; // fresh data => the link is fine again
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
    return expired;
  }
}
