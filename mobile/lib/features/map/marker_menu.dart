import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:maplibre/maplibre.dart';

import '../../core/avatar.dart';
import '../../core/peer_state.dart';
import '../../l10n/app_localizations.dart';
import '../../ui/tokens.dart';
import '../../util/format.dart';
import 'bee_marker.dart';
import 'menu_layout.dart';

class MarkerMenuData {
  const MarkerMenuData({
    required this.identity,
    required this.entry,
    required this.following,
    required this.connected,
    required this.onRename,
    required this.onZoom,
    required this.onToggleFollow,
    this.referenceEntry,
  });

  final Identity identity;
  final PeerEntry entry;
  final bool following;
  final bool connected;
  final PeerEntry? referenceEntry;
  final VoidCallback onRename;
  final VoidCallback onZoom;
  final VoidCallback onToggleFollow;
}

const double _bubbleSize = 38;
const Color _glass = inkGlass;
const Color _hair = hair;
const Color _mist = mist;
const Color _beacon = beacon;
const Curve _pop = Cubic(0.34, 1.56, 0.64, 1);
const List<Offset> _collapsed = [Offset.zero, Offset.zero, Offset.zero, Offset.zero];

class MarkerMenu extends StatefulWidget {
  const MarkerMenu({
    required this.data,
    required this.bounds,
    required this.onClose,
    super.key,
  });

  final MarkerMenuData? data;
  final Rect bounds;
  final VoidCallback onClose;

  @override
  State<MarkerMenu> createState() => _MarkerMenuState();
}

class _MarkerMenuState extends State<MarkerMenu> with TickerProviderStateMixin {
  late final AnimationController _anim = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 220),
  );
  late final Ticker _ticker = createTicker(_tick);
  Duration _lastTick = Duration.zero;

  MarkerMenuData? _shown;
  List<Spring> _springs = List.filled(4, Spring.zero);
  List<Offset> _targets = _collapsed;
  MenuChoice? _choice;

  @override
  void initState() {
    super.initState();
    _shown = widget.data;
    if (_shown != null) _anim.forward();
  }

  @override
  void didUpdateWidget(MarkerMenu old) {
    super.didUpdateWidget(old);
    final data = widget.data;
    if (data == null) {
      if (old.data != null) {
        _anim.reverse();
        _aim(_collapsed);
      }
      return;
    }
    final fresh = old.data == null || _shown?.entry.seed != data.entry.seed;
    _shown = data;
    if (fresh) {
      _springs = List.filled(4, Spring.zero);
      _targets = _collapsed;
      _choice = null;
      _anim.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _ticker.dispose();
    _anim.dispose();
    super.dispose();
  }

  void _aim(List<Offset> targets) {
    _targets = targets;
    if (!_ticker.isActive) {
      _lastTick = Duration.zero;
      _ticker.start();
    }
  }

  void _onLayout(MenuLayout layout) {
    _choice = layout.choice;
    if (widget.data == null) return;
    final targets = [...layout.bubbles, layout.box];
    for (var i = 0; i < 4; i++) {
      if (targets[i] != _targets[i]) {
        _aim(targets);
        return;
      }
    }
  }

  void _tick(Duration elapsed) {
    final dt = (elapsed - _lastTick).inMicroseconds / 1e6;
    _lastTick = elapsed;
    final next = [for (var i = 0; i < 4; i++) springStep(_springs[i], _targets[i], dt)];
    final settled = [for (var i = 0; i < 4; i++) springSettled(next[i], _targets[i])].every((s) => s);
    setState(() {
      _springs = settled ? [for (final t in _targets) Spring(t.dx, t.dy, 0, 0)] : next;
    });
    if (settled) _ticker.stop();
  }

  @override
  Widget build(BuildContext context) {
    final data = _shown;
    final controller = MapController.maybeOf(context);
    final camera = MapCamera.maybeOf(context);
    if (data == null || controller == null || camera == null) return const SizedBox.shrink();

    final anchor = controller.toScreenLocations([
      Geographic(lon: data.entry.position.lng, lat: data.entry.position.lat),
    ]).first;
    final instant = MediaQuery.disableAnimationsOf(context);

    return LayoutBuilder(builder: (context, constraints) {
      final screen = Offset.zero & constraints.biggest;
      if (widget.data != null && !screen.contains(anchor)) {
        WidgetsBinding.instance.addPostFrameCallback((_) => widget.onClose());
      }
      return AnimatedBuilder(
        animation: _anim,
        builder: (context, _) {
          if (_anim.isDismissed) return const SizedBox.shrink();
          final t = instant ? 1.0 : _pop.transform(_anim.value);
          final fade = instant ? 1.0 : Curves.ease.transform((_anim.value / 0.8).clamp(0.0, 1.0));
          Widget piece(Widget child) => Opacity(
                opacity: fade,
                child: Transform.scale(scale: 0.2 + 0.8 * t, child: child),
              );
          final l = L.of(context);
          return IgnorePointer(
            ignoring: widget.data == null,
            child: CustomMultiChildLayout(
              delegate: _MenuDelegate(
                anchor: anchor,
                bounds: widget.bounds,
                springs: _springs,
                previous: _choice,
                instant: instant,
                onLayout: _onLayout,
              ),
              children: [
                LayoutId(
                  id: 0,
                  child: piece(_Bubble(emoji: '✏️', label: l.menuRenameAria, onTap: data.onRename)),
                ),
                LayoutId(
                  id: 1,
                  child: piece(_Bubble(emoji: '🔍', label: l.menuZoomAria, onTap: data.onZoom)),
                ),
                LayoutId(
                  id: 2,
                  child: piece(_Bubble(
                    emoji: '📍',
                    label: data.following ? l.menuUnfollow : l.menuFollow,
                    active: data.following,
                    onTap: data.onToggleFollow,
                  )),
                ),
                LayoutId(id: 3, child: piece(_InfoBox(data: data))),
              ],
            ),
          );
        },
      );
    });
  }
}

class _MenuDelegate extends MultiChildLayoutDelegate {
  _MenuDelegate({
    required this.anchor,
    required this.bounds,
    required this.springs,
    required this.previous,
    required this.instant,
    required this.onLayout,
  });

  final Offset anchor;
  final Rect bounds;
  final List<Spring> springs;
  final MenuChoice? previous;
  final bool instant;
  final void Function(MenuLayout layout) onLayout;

  @override
  void performLayout(Size size) {
    final box = layoutChild(3, const BoxConstraints(minWidth: 130, maxWidth: 220));
    for (var i = 0; i < 3; i++) {
      layoutChild(i, BoxConstraints.tight(const Size.square(_bubbleSize)));
    }
    final layout = layoutMenu(
      anchor: anchor,
      bounds: bounds,
      beeRadius: beeDiscRadius,
      bubble: _bubbleSize,
      box: box,
      previous: previous,
    );
    onLayout(layout);
    final offsets = instant ? [...layout.bubbles, layout.box] : [for (final s in springs) s.position];
    for (var i = 0; i < 3; i++) {
      positionChild(i, anchor + offsets[i] - const Offset(_bubbleSize / 2, _bubbleSize / 2));
    }
    positionChild(3, anchor + offsets[3] - Offset(box.width / 2, box.height / 2));
  }

  @override
  bool shouldRelayout(_MenuDelegate old) =>
      old.anchor != anchor || old.bounds != bounds || old.springs != springs || old.instant != instant;
}

class _InfoBox extends StatelessWidget {
  const _InfoBox({required this.data});

  final MarkerMenuData data;

  @override
  Widget build(BuildContext context) {
    final l = L.of(context);
    final now = DateTime.now();
    final entry = data.entry;

    final lines = <String>[l.infoLastSeen(relTime(entry.ageAt(now), l))];
    if (entry.isSelf) {
      lines.add(data.connected ? l.connOn : l.connOff);
    } else {
      final me = data.referenceEntry;
      if (me != null) {
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
    }

    return Semantics(
      container: true,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: _glass,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: _hair),
          boxShadow: const [BoxShadow(color: Color(0x80000000), blurRadius: 40, offset: Offset(0, 10))],
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                data.identity.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: colorFromHue(data.identity.hue),
                  fontWeight: FontWeight.w700,
                  fontSize: 12.5,
                  height: 1.5,
                ),
              ),
              for (final line in lines)
                Text(
                  line,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: _mist,
                    fontSize: 11.5,
                    fontWeight: FontWeight.w500,
                    height: 1.5,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Bubble extends StatelessWidget {
  const _Bubble({
    required this.emoji,
    required this.label,
    required this.onTap,
    this.active = false,
  });

  final String emoji;
  final String label;
  final VoidCallback onTap;

  final bool active;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: label,
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          width: _bubbleSize,
          height: _bubbleSize,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: active ? _beacon : _glass,
            border: Border.all(color: active ? _beacon : _hair),
            boxShadow: [
              if (active) const BoxShadow(color: Color(0x5934E1B4), spreadRadius: 4),
              const BoxShadow(color: Color(0x80000000), blurRadius: 40, offset: Offset(0, 10)),
            ],
          ),
          child: Text(emoji, style: const TextStyle(fontSize: 16, height: 1)),
        ),
      ),
    );
  }
}
