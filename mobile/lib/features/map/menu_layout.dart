import 'dart:math' as math;
import 'dart:ui';

const double _spread = 50;
const double _gap = 10;
const double _bubbleMargin = 4;
const double _hysteresis = 12;
const List<double> _arcDirections = [-90, -45, -135, 0, 180, 45, 135, 90];
const List<double> _boxTurns = [180, 135, -135, 90, -90];

class MenuChoice {
  const MenuChoice(this.dir, this.turn, this.dist);

  final int dir;
  final int turn;
  final int dist;

  @override
  bool operator ==(Object other) =>
      other is MenuChoice && other.dir == dir && other.turn == turn && other.dist == dist;

  @override
  int get hashCode => Object.hash(dir, turn, dist);
}

class MenuLayout {
  const MenuLayout({required this.bubbles, required this.box, required this.choice});

  final List<Offset> bubbles;
  final Offset box;
  final MenuChoice choice;
}

double _rad(double deg) => deg * math.pi / 180;
double _deg(double rad) => rad * 180 / math.pi;

double _overflow(Rect r, Rect bounds) =>
    math.max(0, bounds.left - r.left) +
    math.max(0, r.right - bounds.right) +
    math.max(0, bounds.top - r.top) +
    math.max(0, r.bottom - bounds.bottom);

bool _overlaps(Rect a, Rect b, double margin) =>
    (a.center.dx - b.center.dx).abs() < (a.width + b.width) / 2 + margin &&
    (a.center.dy - b.center.dy).abs() < (a.height + b.height) / 2 + margin;

List<Rect> _shiftInside(List<Rect> rects, Rect bounds) {
  final left = rects.map((r) => r.left).reduce(math.min);
  final right = rects.map((r) => r.right).reduce(math.max);
  final top = rects.map((r) => r.top).reduce(math.min);
  final bottom = rects.map((r) => r.bottom).reduce(math.max);
  final dx = left < bounds.left
      ? bounds.left - left
      : right > bounds.right
          ? math.max(bounds.right - right, bounds.left - left)
          : 0.0;
  final dy = top < bounds.top
      ? bounds.top - top
      : bottom > bounds.bottom
          ? math.max(bounds.bottom - bottom, bounds.top - top)
          : 0.0;
  return [for (final r in rects) r.shift(Offset(dx, dy))];
}

MenuLayout layoutMenu({
  required Offset anchor,
  required Rect bounds,
  required double beeRadius,
  required double bubble,
  required Size box,
  MenuChoice? previous,
  int count = 3,
}) {
  final ring = beeRadius + _gap + bubble / 2;
  final step = math.max(_spread, _deg(2 * math.asin(math.min(1.0, (bubble + _bubbleMargin) / (2 * ring)))));
  final boxDistances = [beeRadius + _gap, beeRadius + _gap + bubble + _gap];
  final strict = bounds.deflate(_hysteresis);

  List<Rect> bubblesAt(double dir) => [
        for (var i = 0; i < count; i++)
          Rect.fromCenter(
            center: Offset(
              anchor.dx + math.cos(_rad(dir + (i - (count - 1) / 2) * step)) * ring,
              anchor.dy + math.sin(_rad(dir + (i - (count - 1) / 2) * step)) * ring,
            ),
            width: bubble,
            height: bubble,
          ),
      ];

  Rect boxAt(double dir, double dist) {
    final ux = math.cos(_rad(dir));
    final uy = math.sin(_rad(dir));
    return Rect.fromCenter(
      center: Offset(
        anchor.dx + ux * dist + ux * box.width / 2,
        anchor.dy + uy * dist + uy * box.height / 2,
      ),
      width: box.width,
      height: box.height,
    );
  }

  double total(List<Rect> bubbles, Rect b, Rect within) =>
      bubbles.fold(0.0, (s, x) => s + _overflow(x, within)) + _overflow(b, within);

  var passedPrevious = previous == null;
  List<Rect>? bestBubbles;
  Rect? bestBox;
  MenuChoice? bestChoice;
  var bestOverflow = double.infinity;
  for (var d = 0; d < _arcDirections.length; d++) {
    final dir = _arcDirections[d];
    final bubbles = bubblesAt(dir);
    for (var t = 0; t < _boxTurns.length; t++) {
      for (var k = 0; k < boxDistances.length; k++) {
        final b = boxAt(dir + _boxTurns[t], boxDistances[k]);
        final choice = MenuChoice(d, t, k);
        if (choice == previous) passedPrevious = true;
        if (bubbles.any((x) => _overlaps(x, b, 4))) continue;
        final within = passedPrevious ? bounds : strict;
        if (total(bubbles, b, within) == 0) return _result(anchor, bubbles, b, choice);
        final over = total(bubbles, b, bounds);
        if (over < bestOverflow) {
          bestOverflow = over;
          bestBubbles = bubbles;
          bestBox = b;
          bestChoice = choice;
        }
      }
    }
  }
  final shifted = _shiftInside([...bestBubbles!, bestBox!], bounds);
  return _result(anchor, shifted.sublist(0, count), shifted[count], bestChoice!);
}

MenuLayout _result(Offset anchor, List<Rect> bubbles, Rect box, MenuChoice choice) => MenuLayout(
      bubbles: [for (final b in bubbles) b.center - anchor],
      box: box.center - anchor,
      choice: choice,
    );

const double springStiffness = 260;
const double springDamping = 15;
const double _maxStep = 1 / 30;

class Spring {
  const Spring(this.x, this.y, this.vx, this.vy);

  static const Spring zero = Spring(0, 0, 0, 0);

  final double x;
  final double y;
  final double vx;
  final double vy;

  Offset get position => Offset(x, y);
}

Spring springStep(Spring s, Offset target, double dt) {
  final h = math.min(dt, _maxStep);
  final ax = springStiffness * (target.dx - s.x) - springDamping * s.vx;
  final ay = springStiffness * (target.dy - s.y) - springDamping * s.vy;
  final vx = s.vx + ax * h;
  final vy = s.vy + ay * h;
  return Spring(s.x + vx * h, s.y + vy * h, vx, vy);
}

bool springSettled(Spring s, Offset target) =>
    (target.dx - s.x).abs() < 0.3 &&
    (target.dy - s.y).abs() < 0.3 &&
    s.vx.abs() < 3 &&
    s.vy.abs() < 3;
