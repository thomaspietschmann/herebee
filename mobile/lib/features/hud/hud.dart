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
    required this.onInfo,
    super.key,
  });

  final RoomController controller;
  final VoidCallback onFitAll;
  final void Function(String seed) onGoTo;
  final VoidCallback onShareLink;
  final VoidCallback onInfo;

  @override
  Widget build(BuildContext context) {
    final padding = MediaQuery.paddingOf(context);
    return Stack(
      children: [
        Positioned(
          top: padding.top + 10,
          left: 14,
          child: _ConnChip(state: controller.connection),
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
            onInfo: onInfo,
            bottomInset: padding.bottom,
          ),
        ),
      ],
    );
  }
}

class _ConnChip extends StatelessWidget {
  const _ConnChip({required this.state});
  final LinkState state;

  @override
  Widget build(BuildContext context) {
    final l = L.of(context);
    final (color, text) = switch (state) {
      LinkState.on => (const Color(0xFF4ADE80), l.connOn),
      LinkState.off => (const Color(0xFFF87171), l.connOff),
      LinkState.connecting => (const Color(0xFFFBBF24), l.connConnecting),
    };
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xCC0E1116),
        borderRadius: BorderRadius.circular(999),
      ),
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
                  controller.offlineSharers > 0
                      ? l.hereActiveOffline(
                          '${controller.onlineSharers}', '${controller.offlineSharers}')
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
    required this.onInfo,
    required this.bottomInset,
  });

  final VoidCallback onShareLink;
  final VoidCallback onInfo;
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
                // Sharing a position needs the background location service and
                // arrives in Phase 3; until then the app is a watcher, which is
                // a supported way to be in a room.
                const SizedBox(width: 0),
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
