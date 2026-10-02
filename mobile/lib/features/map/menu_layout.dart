import 'dart:math' as math;
import 'dart:ui';

const double _spread = 50;
const double _gap = 10;
const double _bubbleMargin = 4;
const double _hysteresis = 12;
const double _arcStep = 15;
final List<double> _arcDirections = [
  -90,
  for (var k = 1; k <= 12; k++)
    if (k == 12) 90 else ...[-90 + _arcStep * k, -90 - _arcStep * k],
];
const List<double> _sides = [-90, 90, 180, 0];
const int _slides = 3;

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

double _angleGap(double a, double b) {
  final d = ((((a - b) % 360) + 360) % 360).abs();
  return math.min(d, 360 - d);
}

double _clamp(double v, double lo, double hi) => math.min(math.max(v, lo), hi);

MenuLayout layoutMenu({
  required Offset anchor,
  required Rect bounds,
  required double beeRadius,
  required double bubble,
  required Size box,
  MenuChoice? previous,
  int count = 3,
  Rect? outer,
}) {
  final ring = beeRadius + _gap + bubble / 2;
  final step = math.max(_spread, _deg(2 * math.asin(math.min(1.0, (bubble + _bubbleMargin) / (2 * ring)))));
  final boxDistances = [beeRadius + _gap, beeRadius + _gap + bubble + _gap];

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

  Rect boxAt(double side, double dist, int slide, Rect region) {
    final vertical = side == -90 || side == 90;
    final ux = math.cos(_rad(side)).round();
    final uy = math.sin(_rad(side)).round();
    final limit = math.max(0.0, (vertical ? box.width : box.height) / 2 - beeRadius);
    final lo = vertical ? region.left + box.width / 2 - anchor.dx : region.top + box.height / 2 - anchor.dy;
    final hi = vertical ? region.right - box.width / 2 - anchor.dx : region.bottom - box.height / 2 - anchor.dy;
    final fit = _clamp(lo > hi ? lo : _clamp(0, lo, hi), -limit, limit);
    final s = slide == 0 ? fit : slide == 1 ? -limit : limit;
    return Rect.fromCenter(
      center: Offset(
        anchor.dx + ux * (dist + box.width / 2) + (vertical ? s : 0),
        anchor.dy + uy * (dist + box.height / 2) + (vertical ? 0 : s),
      ),
      width: box.width,
      height: box.height,
    );
  }

  double total(List<Rect> bubbles, Rect b, Rect within) =>
      bubbles.fold(0.0, (s, x) => s + _overflow(x, within)) + _overflow(b, within);

  final regions = outer == null ? [bounds] : [bounds, outer];
  final last = regions.last;
  List<Rect>? bestBubbles;
  Rect? bestBox;
  MenuChoice? bestChoice;
  var bestOverflow = double.infinity;
  for (var r = 0; r < regions.length; r++) {
    final region = regions[r];
    final strict = region.deflate(_hysteresis);
    var passedPrevious = previous == null;
    for (var d = 0; d < _arcDirections.length; d++) {
      final dir = _arcDirections[d];
      final bubbles = bubblesAt(dir);
      final sides = [for (var i = 0; i < _sides.length; i++) i]
        ..sort((a, b) {
          final byGap = _angleGap(_sides[a], dir + 180).compareTo(_angleGap(_sides[b], dir + 180));
          return byGap != 0 ? byGap : a.compareTo(b);
        });
      for (final i in sides) {
        for (var k = 0; k < boxDistances.length; k++) {
          for (var v = 0; v < _slides; v++) {
            final choice = MenuChoice(r * _arcDirections.length + d, i * _slides + v, k);
            if (choice == previous) passedPrevious = true;
            final within = passedPrevious ? region : strict;
            final b = boxAt(_sides[i], boxDistances[k], v, within);
            if (bubbles.any((x) => _overlaps(x, b, 4))) continue;
            if (total(bubbles, b, within) == 0) return _result(anchor, bubbles, b, choice);
            final over = total(bubbles, b, last);
            if (over < bestOverflow) {
              bestOverflow = over;
              bestBubbles = bubbles;
              bestBox = b;
              bestChoice = choice;
            }
          }
        }
      }
    }
  }
  return _result(anchor, bestBubbles!, bestBox!, bestChoice!);
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
