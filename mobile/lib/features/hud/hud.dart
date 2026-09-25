/// The floating chrome over the map: brand + connection chip, the roster, and
/// the bottom dock. Port of the HUD in `client/index.html` and
/// `client/src/ui.ts`.
library;

import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../map/bee_marker.dart';
import '../room/room_controller.dart';

class Hud extends StatelessWidget {
  const Hud({
    required this.controller,
    required this.onFitAll,
    required this.onGoTo,
    required this.onShareLink,
    required this.onToggleShare,
    required this.onInfo,
    required this.onRooms,
    super.key,
  });

  final RoomController controller;
  final VoidCallback onFitAll;
  final void Function(String seed) onGoTo;
  final VoidCallback onShareLink;
  final VoidCallback onToggleShare;
  final VoidCallback onInfo;

  /// Opens the rooms sheet: recent rooms and a fresh one.
  final VoidCallback onRooms;

  @override
  Widget build(BuildContext context) {
    final padding = MediaQuery.paddingOf(context);
    return Stack(
      children: [
        Positioned(
          top: padding.top + 10,
          left: 14,
          child: _ConnChip(state: controller.connection, onTap: onRooms),
        ),
        if (controller.entered)
          Positioned(
            top: padding.top + 10,
            right: 14,
            child: _RosterButton(controller: controller, onFitAll: onFitAll, onGoTo: onGoTo),
          ),
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: _Dock(
            onShareLink: onShareLink,
            onToggleShare: onToggleShare,
            onInfo: onInfo,
            sharing: controller.sharing,
            busy: controller.toggling,
            bottomInset: padding.bottom,
          ),
        ),
      ],
    );
  }
}

class _ConnChip extends StatelessWidget {
  const _ConnChip({required this.state, required this.onTap});
  final LinkState state;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l = L.of(context);
    final (color, text) = switch (state) {
      LinkState.on => (const Color(0xFF4ADE80), l.connOn),
      LinkState.off => (const Color(0xFFF87171), l.connOff),
      LinkState.connecting => (const Color(0xFFFBBF24), l.connConnecting),
    };
    // The brand chip doubles as the way to your rooms. A dedicated button
    // would cost HUD space; the chip is already the one fixed landmark.
    return Material(
      color: const Color(0xCC0E1116),
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        key: const ValueKey('rooms-chip'),
        borderRadius: BorderRadius.circular(999),
        onTap: onTap,
        child: Semantics(
          button: true,
          label: l.roomsTitle,
          child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // The dot carries the state for screen readers, as its own node, so
            // a change is announced without re-reading the brand name with it.
            Semantics(
              container: true,
              liveRegion: true,
              label: text,
              child: Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(color: color, shape: BoxShape.circle),
              ),
            ),
            const SizedBox(width: 8),
            const Text.rich(
              TextSpan(
                children: [
                  TextSpan(text: 'Here'),
                  TextSpan(text: 'Bee', style: TextStyle(fontWeight: FontWeight.w800)),
                ],
              ),
              style: TextStyle(color: Colors.white, fontSize: 15, letterSpacing: 0.2),
            ),
          ],
        ),
          ),
        ),
      ),
    );
  }
}

class _RosterButton extends StatelessWidget {
  const _RosterButton({
    required this.controller,
    required this.onFitAll,
    required this.onGoTo,
  });

  final RoomController controller;
  final VoidCallback onFitAll;
  final void Function(String seed) onGoTo;

  @override
  Widget build(BuildContext context) {
    final l = L.of(context);
    final roster = controller.roster();
    final pips = roster.take(4).toList();

    return Row(
      children: [
        Material(
          color: const Color(0xCC0E1116),
          borderRadius: BorderRadius.circular(999),
          child: InkWell(
            borderRadius: BorderRadius.circular(999),
            onTap: () => _openRoster(context),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final r in pips)
                    Padding(
                      padding: const EdgeInsets.only(right: 4),
                      child: Container(
                        width: 10,
                        height: 10,
                        decoration: BoxDecoration(
                          color: colorFromHue(r.identity.hue)
                              .withValues(alpha: r.offline ? 0.4 : 1),
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),
                  Text(
                    l.here('${controller.presence}'),
                    style: const TextStyle(color: Colors.white, fontSize: 13),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        Material(
          color: const Color(0xCC0E1116),
          borderRadius: BorderRadius.circular(999),
          child: InkWell(
            borderRadius: BorderRadius.circular(999),
            onTap: onFitAll,
            child: Padding(
              padding: const EdgeInsets.all(9),
              child: Semantics(
                button: true,
                label: l.fitAll,
                child: const Icon(Icons.fullscreen, size: 18, color: Colors.white),
              ),
            ),
          ),
        ),
      ],
    );
  }

  void _openRoster(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF12161D),
      showDragHandle: true,
      builder: (context) {
        final l = L.of(context);
        final roster = controller.roster();
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(l.participantsTitle,
                    style: const TextStyle(
                        color: Colors.white, fontSize: 18, fontWeight: FontWeight.w700)),
                const SizedBox(height: 4),
                Text(
                  // "active" is everyone present, matching the pill above and
                  // the web client. Using the online SHARERS here instead would
                  // make the headline disagree with the count next to it.
                  controller.offlineSharers > 0
                      ? l.hereActiveOffline(
                          '${controller.presence}', '${controller.offlineSharers}')
                      : l.here('${controller.presence}'),
                  style: const TextStyle(color: Colors.white54, fontSize: 13),
                ),
                const SizedBox(height: 12),
                if (roster.isEmpty)
                  Text(l.noSharers, style: const TextStyle(color: Colors.white70))
                else
                  for (final r in roster)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Container(
                        width: 14,
                        height: 14,
                        decoration: BoxDecoration(
                          color: colorFromHue(r.identity.hue)
                              .withValues(alpha: r.offline ? 0.4 : 1),
                          shape: BoxShape.circle,
                        ),
                      ),
                      title: Text(r.identity.name,
                          style: const TextStyle(color: Colors.white, fontSize: 15)),
                      subtitle: r.offline
                          ? Text(l.offlineStatus,
                              style: const TextStyle(color: Colors.white38, fontSize: 12))
                          : null,
                      onTap: () {
                        Navigator.of(context).pop();
                        onGoTo(r.seed);
                      },
                    ),
                if (controller.watchers > 0) ...[
                  const SizedBox(height: 8),
                  Text(l.watchingLine('${controller.watchers}'),
                      style: const TextStyle(color: Colors.white54, fontSize: 13)),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}

class _Dock extends StatelessWidget {
  const _Dock({
    required this.onShareLink,
    required this.onToggleShare,
    required this.onInfo,
    required this.sharing,
    required this.busy,
    required this.bottomInset,
  });

  final VoidCallback onShareLink;
  final VoidCallback onToggleShare;
  final VoidCallback onInfo;
  final bool sharing;

  /// A start or stop is in flight. The control is disabled rather than hidden,
  /// so the button does not move under the user's finger.
  final bool busy;
  final double bottomInset;

  @override
  Widget build(BuildContext context) {
    final l = L.of(context);
    return DecoratedBox(
      // A plain gradient is not enough over a light basemap: the hint text sat
      // on street labels and was unreadable. Ramp to near-opaque well before the
      // text starts.
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0x000E1116), Color(0xCC0E1116), Color(0xF20E1116)],
          stops: [0, 0.45, 1],
        ),
      ),
      child: Padding(
        padding: EdgeInsets.fromLTRB(16, 40, 16, 14 + bottomInset),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              l.hint,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white70, fontSize: 12, height: 1.35),
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                OutlinedButton(
                  onPressed: onShareLink,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white,
                    side: const BorderSide(color: Color(0x33FFFFFF)),
                    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                  ),
                  child: Text(l.shareLink),
                ),
                const SizedBox(width: 10),
                // The primary action. It reads "Stop sharing" while active, so
                // turning it off is never more than one tap away.
                FilledButton(
                  onPressed: busy ? null : onToggleShare,
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                    backgroundColor:
                        sharing ? const Color(0xFF3A2020) : const Color(0xFFF5B301),
                    foregroundColor: sharing ? Colors.white : const Color(0xFF17120D),
                  ),
                  child: Text(
                    sharing ? l.stopSharing : l.shareLocation,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
                const SizedBox(width: 10),
                IconButton(
                  onPressed: onInfo,
                  icon: const Icon(Icons.info_outline),
                  color: Colors.white70,
                  tooltip: l.infoAria,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
