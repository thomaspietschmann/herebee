import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:maplibre/maplibre.dart';

const double followBurstDistance = 160;
const double _rubberReach = 48;

Offset followRubber(Offset travel) {
  final d = travel.distance;
  if (d == 0) return Offset.zero;
  final visible = _rubberReach * (1 - 1 / (d * 0.55 / _rubberReach + 1));
  return travel / d * visible;
}

class FollowDragLayer extends StatefulWidget {
  const FollowDragLayer({
    required this.stretch,
    required this.onActive,
    required this.onBurst,
    required this.onSnapBack,
    required this.onTap,
    required this.onDone,
    super.key,
  });

  final ValueNotifier<double> stretch;
  final ValueChanged<bool> onActive;
  final VoidCallback onBurst;
  final VoidCallback onSnapBack;
  final VoidCallback onTap;
  final VoidCallback onDone;

  @override
  State<FollowDragLayer> createState() => _FollowDragLayerState();
}

class _FollowDragLayerState extends State<FollowDragLayer> {
  final Map<int, Offset> _pointers = {};
  Offset _start = Offset.zero;
  Offset _last = Offset.zero;
  Offset _applied = Offset.zero;
  bool _burst = false;
  bool _multi = false;
  bool _moved = false;
  DateTime _downAt = DateTime.now();
  DateTime? _lastTapAt;
  double _pinchDistance = 0;
  double _pinchZoom = 0;

  MapController? get _map => MapController.maybeOf(context);

  void _shift(Offset delta) {
    final map = _map;
    if (map == null || delta == Offset.zero) return;
    final center = map.toScreenLocation(map.getCamera().center);
    unawaitedMove(map.moveCamera(center: map.toLngLat(center - delta)));
  }

  void _beginSingle(Offset at) {
    _start = at;
    _last = at;
  }

  void _beginPinch() {
    final p = _pointers.values.take(2).toList();
    _pinchDistance = (p[0] - p[1]).distance;
    _pinchZoom = _map?.getCamera().zoom ?? 0;
  }

  void _relax() {
    if (_burst || _applied == Offset.zero && widget.stretch.value == 0) return;
    _applied = Offset.zero;
    widget.stretch.value = 0;
    widget.onSnapBack();
  }

  void _down(PointerDownEvent e) {
    _pointers[e.pointer] = e.localPosition;
    if (_pointers.length == 1) {
      _burst = false;
      _multi = false;
      _moved = false;
      _applied = Offset.zero;
      _downAt = DateTime.now();
      _beginSingle(e.localPosition);
      widget.onActive(true);
    } else {
      _multi = true;
      _relax();
      if (_pointers.length == 2) _beginPinch();
    }
  }

  void _move(PointerMoveEvent e) {
    if (!_pointers.containsKey(e.pointer)) return;
    _pointers[e.pointer] = e.localPosition;
    if (_pointers.length >= 2) {
      final p = _pointers.values.take(2).toList();
      final d = (p[0] - p[1]).distance;
      if (_pinchDistance <= 0 || d <= 0) return;
      final zoom = _pinchZoom + math.log(d / _pinchDistance) / math.ln2;
      final map = _map;
      if (map != null) unawaitedMove(map.moveCamera(zoom: zoom));
      return;
    }
    final at = e.localPosition;
    if ((at - _start).distance > kTouchSlop) _moved = true;
    if (_burst) {
      _shift(at - _last);
      _last = at;
      return;
    }
    final travel = at - _start;
    final progress = travel.distance / followBurstDistance;
    if (progress >= 1) {
      _burst = true;
      _shift(at - _start - _applied);
      _applied = Offset.zero;
      _last = at;
      widget.stretch.value = 0;
      widget.onBurst();
      return;
    }
    final visible = followRubber(travel);
    _shift(visible - _applied);
    _applied = visible;
    _last = at;
    widget.stretch.value = progress;
  }

  void _up(PointerEvent e) {
    if (_pointers.remove(e.pointer) == null) return;
    if (_pointers.length == 1) {
      _beginSingle(_pointers.values.first);
      return;
    }
    if (_pointers.length >= 2) {
      _beginPinch();
      return;
    }
    final tapped =
        e is PointerUpEvent &&
        !_moved &&
        !_multi &&
        !_burst &&
        DateTime.now().difference(_downAt) < const Duration(milliseconds: 300);
    _relax();
    widget.onActive(false);
    if (tapped) _tap();
    if (_burst) {
      _burst = false;
      widget.onDone();
    }
  }

  void _tap() {
    final now = DateTime.now();
    final last = _lastTapAt;
    if (last != null && now.difference(last) < const Duration(milliseconds: 300)) {
      _lastTapAt = null;
      final map = _map;
      if (map != null) {
        unawaitedMove(
          map.animateCamera(zoom: map.getCamera().zoom + 1, nativeDuration: const Duration(milliseconds: 250)),
        );
      }
      return;
    }
    _lastTapAt = now;
    widget.onTap();
  }

  @override
  Widget build(BuildContext context) => Positioned.fill(
    child: Listener(
      behavior: HitTestBehavior.opaque,
      onPointerDown: _down,
      onPointerMove: _move,
      onPointerUp: _up,
      onPointerCancel: _up,
      child: const SizedBox.expand(),
    ),
  );
}

void unawaitedMove(Future<void> move) => move.catchError((Object _) {});

class FollowPin extends StatefulWidget {
  const FollowPin({required this.stretch, required this.bursting, super.key});

  final ValueListenable<double> stretch;
  final bool bursting;

  @override
  State<FollowPin> createState() => _FollowPinState();
}

class _FollowPinState extends State<FollowPin> with TickerProviderStateMixin {
  late final AnimationController _burst = AnimationController(vsync: this, duration: const Duration(milliseconds: 520));
  late final AnimationController _settle = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 420),
  );
  double _from = 0;

  @override
  void initState() {
    super.initState();
    widget.stretch.addListener(_onStretch);
    if (widget.bursting) _burst.forward();
  }

  @override
  void didUpdateWidget(FollowPin old) {
    super.didUpdateWidget(old);
    if (old.stretch != widget.stretch) {
      old.stretch.removeListener(_onStretch);
      widget.stretch.addListener(_onStretch);
    }
    if (widget.bursting && !old.bursting) _burst.forward(from: 0);
    if (!widget.bursting && old.bursting) _burst.reset();
  }

  void _onStretch() {
    if (widget.stretch.value == 0 && _from > 0 && !widget.bursting) {
      _settle.forward(from: 0);
    } else {
      _settle.value = 1;
    }
    if (widget.stretch.value > 0) _from = widget.stretch.value;
  }

  @override
  void dispose() {
    widget.stretch.removeListener(_onStretch);
    _burst.dispose();
    _settle.dispose();
    super.dispose();
  }

  double _inflation() {
    final s = widget.stretch.value;
    if (s > 0) return s;
    if (!_settle.isAnimating) return 0;
    return _from * (1 - Curves.elasticOut.transform(_settle.value));
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 96,
      height: 96,
      child: AnimatedBuilder(
        animation: Listenable.merge([widget.stretch, _burst, _settle]),
        builder: (context, _) {
          final b = _burst.value;
          if (widget.bursting) {
            final pop = (b / 0.22).clamp(0.0, 1.0);
            return CustomPaint(
              painter: _BurstPainter(b),
              child: Center(
                child: Opacity(
                  opacity: 1 - pop,
                  child: Transform.scale(
                    scale: 1.9 + 0.8 * pop,
                    alignment: Alignment.bottomCenter,
                    child: const _PinGlyph(),
                  ),
                ),
              ),
            );
          }
          final p = _inflation();
          final wobble = p > 0.6 ? math.sin(DateTime.now().millisecondsSinceEpoch / 28) * 0.04 * (p - 0.6) / 0.4 : 0.0;
          return Center(
            child: Transform.translate(
              offset: Offset(0, -21 * 0.28 * math.pow(p, 1.2)),
              child: Transform.scale(
                scaleX: 1 + 0.9 * math.pow(p, 1.3) + wobble,
                scaleY: 1 + 0.9 * math.pow(p, 1.3) - wobble,
                alignment: Alignment.bottomCenter,
                child: const _PinGlyph(),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _PinGlyph extends StatelessWidget {
  const _PinGlyph();

  @override
  Widget build(BuildContext context) => const Text(
    '📍',
    style: TextStyle(
      fontSize: 22,
      height: 1,
      shadows: [Shadow(color: Color(0x80000000), blurRadius: 6, offset: Offset(0, 2))],
    ),
  );
}

class _BurstPainter extends CustomPainter {
  _BurstPainter(this.t);
  final double t;

  static const _colors = [Color(0xFFE53935), Color(0xFFFFB300), Color(0xFFFFFFFF)];

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final ease = Curves.easeOutCubic.transform(t);
    final fade = (1 - t).clamp(0.0, 1.0);
    canvas.drawCircle(
      c,
      8 + 34 * ease,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3 * fade
        ..color = const Color(0xFFE53935).withValues(alpha: 0.8 * fade),
    );
    const n = 10;
    for (var i = 0; i < n; i++) {
      final a = i / n * 2 * math.pi + (i.isEven ? 0.12 : -0.08);
      final r = (i.isEven ? 40 : 30) * ease;
      final p = c + Offset(math.cos(a), math.sin(a)) * r;
      canvas.drawCircle(
        p,
        (i.isEven ? 3.5 : 2.5) * (1 - 0.6 * t),
        Paint()..color = _colors[i % _colors.length].withValues(alpha: fade),
      );
    }
  }

  @override
  bool shouldRepaint(_BurstPainter old) => old.t != t;
}

class FollowSwell extends StatelessWidget {
  const FollowSwell({required this.stretch, required this.child, this.amount = 0.28, super.key});

  final ValueListenable<double> stretch;
  final double amount;
  final Widget child;

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<double>(
    valueListenable: stretch,
    builder: (context, p, child) => AnimatedScale(
      scale: 1 + amount * math.pow(p, 1.2),
      duration: p == 0 ? const Duration(milliseconds: 420) : Duration.zero,
      curve: Curves.elasticOut,
      child: child,
    ),
    child: child,
  );
}
