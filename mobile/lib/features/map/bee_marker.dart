/// One bee on the map. Mirrors the `.mk` marker in the web client: a pulse ring
/// while the fix is fresh, a heading arrow once the peer is genuinely moving,
/// the seeded bee face on a coloured disc, and a name label that carries the
/// status suffix.
///
/// Freshness is expressed visually rather than in words wherever possible, so a
/// glance at the map tells you who is live without reading every label.
library;

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../core/avatar.dart';
import '../../core/peer_state.dart';
import '../../l10n/app_localizations.dart';
import '../../util/format.dart';

/// Logical size of the whole marker widget, label included. WidgetLayer needs
/// this up front to place the marker, so it is a constant rather than measured:
/// it must fit the disc, its pulse ring, and TWO lines of label. Names like
/// "Cheeky Nectar Hunter" wrap, and a height that only fits one line clips the
/// second without any other symptom.
const Size beeMarkerSize = Size(148, 124);

const double _discSize = 52;

Color colorFromHue(int hue) => HSLColor.fromAHSL(1, hue.toDouble(), 0.72, 0.56).toColor();

/// Status text appended to the name, or null when nothing is amiss.
String? statusSuffix(PeerEntry entry, DateTime now, L l) {
  if (entry.offline) return l.offlineStatus;
  final tier = entry.tierAt(now);
  if (tier == Tier.fresh) return null;
  final age = relTime(entry.ageAt(now), l);
  return tier == Tier.ghost ? l.noSignalLong(age) : l.noSignal(age);
}

class BeeMarker extends StatelessWidget {
  const BeeMarker({
    required this.identity,
    required this.entry,
    required this.now,
    required this.onTap,
    this.isSelf = false,
    super.key,
  });

  final Identity identity;
  final PeerEntry entry;
  final DateTime now;
  final VoidCallback onTap;
  final bool isSelf;

  @override
  Widget build(BuildContext context) {
    final l = L.of(context);
    final tier = entry.tierAt(now);
    final color = colorFromHue(identity.hue);

    // Ghosts and dropped links fade out; a live peer stays fully saturated.
    final opacity = entry.offline
        ? 0.45
        : switch (tier) { Tier.fresh => 1.0, Tier.stale => 0.75, Tier.ghost => 0.5 };

    final suffix = statusSuffix(entry, now, l);
    final label = suffix == null ? identity.name : '${identity.name} · $suffix';

    return SizedBox.fromSize(
      size: beeMarkerSize,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: _discSize + 24,
              height: _discSize + 24,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  if (tier == Tier.fresh && !entry.offline) _PulseRing(color: color),
                  if (entry.showsHeading())
                    Transform.rotate(
                      angle: entry.position.hdg! * 3.141592653589793 / 180,
                      child: _HeadingArrow(color: color),
                    ),
                  Opacity(
                    opacity: opacity,
                    child: Container(
                      width: _discSize,
                      height: _discSize,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: const Color(0xFF0E1116),
                        border: Border.all(color: color, width: isSelf ? 4 : 3),
                        boxShadow: const [
                          BoxShadow(color: Color(0x66000000), blurRadius: 8, offset: Offset(0, 2)),
                        ],
                      ),
                      padding: const EdgeInsets.all(3),
                      child: SvgPicture.string(identity.svg),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 2),
            Flexible(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: const Color(0xCC0E1116),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                  child: Text(
                    label,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: opacity),
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      height: 1.15,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Slow breathing ring behind a fresh marker. Honours the platform's
/// reduced-motion setting, where it becomes a static ring.
class _PulseRing extends StatefulWidget {
  const _PulseRing({required this.color});
  final Color color;

  @override
  State<_PulseRing> createState() => _PulseRingState();
}

class _PulseRingState extends State<_PulseRing> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1800),
  );

  @override
  void initState() {
    super.initState();
    _c.repeat();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.disableAnimationsOf(context)) {
      return _ring(widget.color, 1.15, 0.35);
    }
    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) => _ring(widget.color, 1 + _c.value * 0.45, (1 - _c.value) * 0.45),
    );
  }

  Widget _ring(Color color, double scale, double opacity) => Transform.scale(
        scale: scale,
        child: Container(
          width: _discSize,
          height: _discSize,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: color.withValues(alpha: opacity), width: 2),
          ),
        ),
      );
}

class _HeadingArrow extends StatelessWidget {
  const _HeadingArrow({required this.color});
  final Color color;

  @override
  Widget build(BuildContext context) => SizedBox(
        width: _discSize + 22,
        height: _discSize + 22,
        child: Align(
          alignment: Alignment.topCenter,
          child: Icon(Icons.navigation, size: 16, color: color),
        ),
      );
}
