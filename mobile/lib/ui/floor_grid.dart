import 'package:flutter/widgets.dart';

/// The synthwave floor grid: thin lines every 32 px rising from the bottom
/// edge and fading out towards the top, plus a soft wash of the same colour.
/// Port of `:root[data-map-theme="synthwave"] #app::after` in
/// client/src/style.css. Purely decorative; wrap it in an IgnorePointer.
class FloorGrid extends StatelessWidget {
  const FloorGrid({required this.line, this.wash, super.key});

  final Color line;
  final Color? wash;

  @override
  Widget build(BuildContext context) => CustomPaint(painter: _FloorGridPainter(line, wash));
}

class _FloorGridPainter extends CustomPainter {
  _FloorGridPainter(this.line, this.wash);

  final Color line;
  final Color? wash;

  static const double _step = 32;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final wash = this.wash;
    if (wash != null) {
      canvas.drawRect(
        rect,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.bottomCenter,
            end: Alignment.topCenter,
            colors: [wash, wash.withValues(alpha: 0)],
            stops: const [0, 0.7],
          ).createShader(rect),
      );
    }
    // Draw the lines into a layer, then fade the layer out upwards: the same
    // mask the web uses (opaque at the bottom, half at 45 %, gone at the top).
    canvas.saveLayer(rect, Paint());
    final paint = Paint()
      ..color = line
      ..strokeWidth = 1;
    for (var x = 0.5; x < size.width; x += _step) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    for (var y = size.height - 0.5; y > 0; y -= _step) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
    canvas.drawRect(
      rect,
      Paint()
        ..blendMode = BlendMode.dstIn
        ..shader = const LinearGradient(
          begin: Alignment.bottomCenter,
          end: Alignment.topCenter,
          colors: [Color(0xFF000000), Color(0x80000000), Color(0x00000000)],
          stops: [0, 0.45, 1],
        ).createShader(rect),
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(_FloorGridPainter old) => old.line != line || old.wash != wash;
}

/// The faint square grid inside synthwave sheets (24 px), as in the web's
/// `.sheet-panel` background. Purely decorative.
class PanelGrid extends StatelessWidget {
  const PanelGrid({required this.line, super.key});

  final Color line;

  @override
  Widget build(BuildContext context) => CustomPaint(painter: _PanelGridPainter(line));
}

class _PanelGridPainter extends CustomPainter {
  _PanelGridPainter(this.line);

  final Color line;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = line
      ..strokeWidth = 1;
    for (var x = 0.5; x < size.width; x += 24) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    for (var y = 0.5; y < size.height; y += 24) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(_PanelGridPainter old) => old.line != line;
}
