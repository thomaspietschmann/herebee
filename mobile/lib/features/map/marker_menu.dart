/// The action bubbles and info box shown when a bee is tapped. Mirrors
/// `openMenu` in `client/src/markers.ts`: rename, follow, and a small box with
/// last-seen, distance and link state.
///
/// It is anchored to the screen centre-top rather than to the marker: the marker
/// moves with the camera while the menu is open, and a menu that chases it is
/// harder to hit than one that stays put.
library;

import 'package:flutter/material.dart';

import '../../core/avatar.dart';
import '../../core/peer_state.dart';
import '../../l10n/app_localizations.dart';
import '../../util/format.dart';
import 'bee_marker.dart';

class MarkerMenu extends StatelessWidget {
  const MarkerMenu({
    required this.identity,
    required this.entry,
    required this.following,
    required this.onRename,
    required this.onToggleFollow,
    required this.onClose,
    this.referenceEntry,
    super.key,
  });

  final Identity identity;
  final PeerEntry entry;
  final bool following;

  /// Our own marker, used for the distance line. Null while we only watch.
  final PeerEntry? referenceEntry;

  final VoidCallback onRename;
  final VoidCallback onToggleFollow;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final l = L.of(context);
    final now = DateTime.now();
    final color = colorFromHue(identity.hue);

    final lines = <String>[l.infoLastSeen(relTime(entry.ageAt(now), l))];
    final me = referenceEntry;
    if (me != null && me.seed != entry.seed) {
      lines.add(l.infoDistance(formatDistance(distanceMeters(
        me.position.lat,
        me.position.lng,
        entry.position.lat,
        entry.position.lng,
      ))));
    }
    lines.add(entry.offline
        ? l.offlineStatus
        : entry.tierAt(now) == Tier.fresh
            ? l.statusOnline
            : l.statusNoSignal);

    return Positioned(
      left: 12,
      right: 12,
      top: MediaQuery.paddingOf(context).top + 64,
      child: Semantics(
        container: true,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: const Color(0xF20E1116),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: color.withValues(alpha: 0.5)),
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 8, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        identity.name,
                        style: TextStyle(
                          color: color,
                          fontWeight: FontWeight.w700,
                          fontSize: 15,
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: onClose,
                      icon: const Icon(Icons.close, size: 18),
                      color: Colors.white70,
                      tooltip: l.close,
                    ),
                  ],
                ),
                for (final line in lines)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 2),
                    child: Text(line,
                        style: const TextStyle(color: Colors.white70, fontSize: 13)),
                  ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    _Bubble(
                      icon: Icons.edit_outlined,
                      label: l.menuRenameAria,
                      onTap: onRename,
                    ),
                    const SizedBox(width: 10),
                    _Bubble(
                      icon: following ? Icons.location_off_outlined : Icons.my_location,
                      label: following ? l.menuUnfollow : l.menuFollow,
                      active: following,
                      color: color,
                      onTap: onToggleFollow,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Bubble extends StatelessWidget {
  const _Bubble({
    required this.icon,
    required this.label,
    required this.onTap,
    this.active = false,
    this.color,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool active;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final accent = color ?? Colors.white;
    return Semantics(
      button: true,
      label: label,
      child: Material(
        color: active ? accent.withValues(alpha: 0.18) : const Color(0x1AFFFFFF),
        borderRadius: BorderRadius.circular(999),
        child: InkWell(
          borderRadius: BorderRadius.circular(999),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 16, color: active ? accent : Colors.white70),
                const SizedBox(width: 6),
                Text(label,
                    style: TextStyle(
                      color: active ? accent : Colors.white70,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    )),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
