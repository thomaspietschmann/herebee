/// One bee on the map. Mirrors the `.mk` marker in the web client: a pulse ring
/// while the fix is fresh, a heading arrow once the peer is genuinely moving,
/// the seeded bee face on a coloured disc, and a name label that carries the
/// status suffix.
///
/// Freshness is expressed visually rather than in words wherever possible, so a
/// glance at the map tells you who is live without reading every label.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../core/avatar.dart';
import '../../core/peer_state.dart';
import '../../l10n/app_localizations.dart';
import '../../util/format.dart';
import '../../ui/tokens.dart';
import 'follow_drag.dart';

const double _sayReserve = 64;

const Size beeMarkerSize = Size(240, 174);

const double _discSize = 42;

const double _center = 38;

const double beeDiscRadius = _discSize / 2;

const double _pinLift = 22;

const Alignment beeMarkerAlignment = Alignment(0, (_sayReserve + _center) / (174 / 2) - 1);

const String _pictographicPattern = r'\p{Extended_Pictographic}';
const String _emojiOnlyPattern = r'^(?:\p{Extended_Pictographic}|\p{Emoji_Component}|\u200D|\uFE0F|\s){1,24}$';
final RegExp _emojiOnly = RegExp(_emojiOnlyPattern, unicode: true);
final RegExp _pictographic = RegExp(_pictographicPattern, unicode: true);

bool isEmojiOnly(String text) =>
    _emojiOnly.hasMatch(text) &&
    _pictographic.allMatches(text).length <= 3 &&
    _pictographic.hasMatch(text);

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
    this.menuOpen = false,
    this.bubblesVisible = true,
    this.followStretch,
    this.pinBursting = false,
    super.key,
  });

  final Identity identity;
  final PeerEntry entry;
  final DateTime now;
  final VoidCallback onTap;
  final bool isSelf;

  final bool menuOpen;

  final bool bubblesVisible;

  final ValueListenable<double>? followStretch;

  final bool pinBursting;

  @override
  Widget build(BuildContext context) {
    final l = L.of(context);
    final tier = entry.tierAt(now);
    final color = colorFromHue(identity.hue);

    final (opacity, grey) = entry.offline
        ? (0.5, 0.85)
        : switch (tier) { Tier.fresh => (1.0, 0.0), Tier.stale => (0.75, 0.0), Tier.ghost => (0.5, 0.9) };

    final message = entry.message;
    final t = HereBeeTokens.of(context);
    final suffix = statusSuffix(entry, now, l);
    final label = suffix == null ? identity.name : '${identity.name} · $suffix';
    final stretch = followStretch;
    final pinLift = stretch == null ? 0.0 : _pinLift;

    final disc = Container(
      width: _discSize,
      height: _discSize,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: t.ink2,
        border: Border.all(color: entry.offline ? t.signal : color, width: isSelf ? 3 : 2.5),
        boxShadow: [
          // Synthwave: the identity colour glows around the disc.
          if (t.chromeGlow.isNotEmpty) ...[
            BoxShadow(color: color, blurRadius: 14),
            BoxShadow(color: color, blurRadius: 3),
          ],
          const BoxShadow(color: Color(0x66000000), blurRadius: 14, offset: Offset(0, 4)),
          const BoxShadow(color: Color(0x4D000000), spreadRadius: 1),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: SvgPicture.string(identity.svg),
    );

    final tag = DecoratedBox(
      decoration: BoxDecoration(
        color: isSelf ? t.mist : t.inkGlass,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: t.hair),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: isSelf ? t.ink : t.mist,
            fontSize: 11,
            fontWeight: FontWeight.w600,
            height: 1,
          ),
        ),
      ),
    );

    return SizedBox.fromSize(
      size: beeMarkerSize,
      child: Opacity(
        opacity: opacity,
        child: ColorFiltered(
          colorFilter: ColorFilter.matrix(_greyscale(grey)),
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              if (message != null && bubblesVisible)
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: beeMarkerSize.height - _sayReserve - _center + beeDiscRadius + 4 + pinLift,
                  child: Center(
                    child: IgnorePointer(
                      child: AnimatedOpacity(
                        opacity: menuOpen ? 0 : 1,
                        duration: const Duration(milliseconds: 180),
                        child: _SayBubble(
                          key: ValueKey(entry.messageAt),
                          text: message,
                          color: color,
                        ),
                      ),
                    ),
                  ),
                ),
              Positioned(
                left: beeMarkerSize.width / 2 - _center,
                top: _sayReserve,
                width: _center * 2,
                height: _center * 2,
                child: Stack(
                  alignment: Alignment.center,
                  clipBehavior: Clip.none,
                  children: [
                    if (tier == Tier.fresh && !entry.offline) _PulseRing(color: color),
                    if (entry.showsHeading())
                      Transform.rotate(
                        angle: entry.position.hdg! * 3.141592653589793 / 180,
                        child: _HeadingArrow(color: color),
                      ),
                    if (stretch == null)
                      GestureDetector(onTap: onTap, child: disc)
                    else
                      FollowSwell(stretch: stretch, child: GestureDetector(onTap: onTap, child: disc)),
                    if (message != null && !bubblesVisible)
                      Positioned(
                        top: _center - beeDiscRadius - 2,
                        right: _center - beeDiscRadius - 2,
                        child: IgnorePointer(
                          child: Container(
                            width: 14,
                            height: 14,
                            decoration: BoxDecoration(
                              color: color,
                              shape: BoxShape.circle,
                              border: Border.all(color: t.ink, width: 2),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              if (stretch != null)
                Positioned(
                  left: beeMarkerSize.width / 2 - 48,
                  top: _sayReserve + _center - beeDiscRadius - 11 - 48,
                  child: IgnorePointer(
                    child: FollowPin(stretch: stretch, bursting: pinBursting),
                  ),
                ),
              Positioned(
                top: _sayReserve + _center + 25,
                left: 0,
                right: 0,
                child: Center(
                  child: IgnorePointer(
                    ignoring: menuOpen,
                    child: AnimatedOpacity(
                      opacity: menuOpen ? 0 : 1,
                      duration: const Duration(milliseconds: 180),
                      child: GestureDetector(onTap: onTap, child: tag),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SayBubble extends StatelessWidget {
  const _SayBubble({required this.text, required this.color, super.key});

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final t = HereBeeTokens.of(context);
    final emoji = isEmojiOnly(text);
    final bubble = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 180),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: t.inkGlass,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: color, width: 1.5),
              boxShadow: const [BoxShadow(color: Color(0x66000000), blurRadius: 14, offset: Offset(0, 4))],
            ),
            child: Padding(
              padding: emoji
                  ? const EdgeInsets.symmetric(horizontal: 8, vertical: 3)
                  : const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              child: Text(
                text,
                maxLines: emoji ? 1 : 3,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: emoji
                    ? const TextStyle(fontSize: 22, height: 1.1)
                    : TextStyle(color: t.mist, fontSize: 12, fontWeight: FontWeight.w600, height: 1.3),
              ),
            ),
          ),
        ),
        CustomPaint(size: const Size(10, 6), painter: _TailPainter(color)),
      ],
    );
    if (MediaQuery.disableAnimationsOf(context)) return bubble;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 340),
      curve: const Cubic(0.34, 1.56, 0.64, 1),
      builder: (context, t, child) => Opacity(
        opacity: t.clamp(0.0, 1.0),
        child: Transform.scale(scale: 0.3 + 0.7 * t, alignment: Alignment.bottomCenter, child: child),
      ),
      child: bubble,
    );
  }
}

class _TailPainter extends CustomPainter {
  _TailPainter(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawPath(
      Path()
        ..moveTo(0, 0)
        ..lineTo(size.width, 0)
        ..lineTo(size.width / 2, size.height)
        ..close(),
      Paint()..color = color,
    );
  }

  @override
  bool shouldRepaint(_TailPainter old) => old.color != color;
}

List<double> _greyscale(double amount) {
  final a = 1 - amount;
  const r = 0.2126, g = 0.7152, b = 0.0722;
  return [
    r + a * (1 - r), g - a * g, b - a * b, 0, 0,
    r - a * r, g + a * (1 - g), b - a * b, 0, 0,
    r - a * r, g - a * g, b + a * (1 - b), 0, 0,
    0, 0, 0, 1, 0,
  ];
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
    duration: const Duration(milliseconds: 2400),
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
    if (MediaQuery.disableAnimationsOf(context)) return const SizedBox.shrink();
    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) {
        final t = const Cubic(0, 0, 0.2, 1).transform((_c.value / 0.8).clamp(0.0, 1.0));
        return Transform.scale(
          scale: 0.6 + 1.5 * t,
          child: Container(
            width: _discSize,
            height: _discSize,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: widget.color.withValues(alpha: 0.5 * (1 - t)),
            ),
          ),
        );
      },
    );
  }
}

class _HeadingArrow extends StatelessWidget {
  const _HeadingArrow({required this.color});
  final Color color;

  @override
  Widget build(BuildContext context) => CustomPaint(
        size: const Size.square(_center * 2),
        painter: _ArrowPainter(color),
      );
}

class _ArrowPainter extends CustomPainter {
  _ArrowPainter(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final top = size.height / 2 - 33;
    canvas.drawPath(
      Path()
        ..moveTo(cx, top)
        ..lineTo(cx + 6, top + 9)
        ..lineTo(cx - 6, top + 9)
        ..close(),
      Paint()..color = color,
    );
  }

  @override
  bool shouldRepaint(_ArrowPainter old) => old.color != color;
}
