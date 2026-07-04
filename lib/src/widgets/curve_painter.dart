import 'package:flutter/material.dart';

import '../models.dart';
import '../util.dart';

/// A read-only 24h preview of a temperature curve: setpoint (y, 16–30°)
/// over the day (x, 00:00–24:00), with a filled area under the line.
class CurveChart extends StatelessWidget {
  final List<CurvePoint> points;
  final Color accent;
  const CurveChart({super.key, required this.points, required this.accent});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      height: 140,
      width: double.infinity,
      child: CustomPaint(
        painter: _CurvePainter(
          points: points,
          accent: accent,
          grid: scheme.outlineVariant,
          label: scheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

class _CurvePainter extends CustomPainter {
  final List<CurvePoint> points;
  final Color accent;
  final Color grid;
  final Color label;
  _CurvePainter({
    required this.points,
    required this.accent,
    required this.grid,
    required this.label,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final gridPaint = Paint()
      ..color = grid
      ..strokeWidth = 1;
    // horizontal gridlines at 16/23/30
    for (final t in [kMinTemp, (kMinTemp + kMaxTemp) / 2, kMaxTemp]) {
      final y = _y(t, size);
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
      final tp = TextPainter(
        text: TextSpan(
            text: '${t.toStringAsFixed(0)}°',
            style: TextStyle(color: label, fontSize: 10)),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(2, y - 12));
    }
    if (points.isEmpty) return;

    final sorted = [...points]..sort((a, b) => minutesOf(a.time).compareTo(minutesOf(b.time)));
    final path = Path();
    final fill = Path();
    for (var i = 0; i < sorted.length; i++) {
      final x = size.width * (minutesOf(sorted[i].time) / 1440.0);
      final y = _y(sorted[i].temperature, size);
      if (i == 0) {
        path.moveTo(x, y);
        fill.moveTo(x, size.height);
        fill.lineTo(x, y);
      } else {
        path.lineTo(x, y);
        fill.lineTo(x, y);
      }
    }
    fill.lineTo(size.width * (minutesOf(sorted.last.time) / 1440.0), size.height);
    fill.close();
    canvas.drawPath(fill, Paint()..color = accent.withValues(alpha: 0.15));
    canvas.drawPath(
      path,
      Paint()
        ..color = accent
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5
        ..strokeJoin = StrokeJoin.round,
    );
    for (final p in sorted) {
      final x = size.width * (minutesOf(p.time) / 1440.0);
      canvas.drawCircle(Offset(x, _y(p.temperature, size)), 3.5, Paint()..color = accent);
    }
  }

  double _y(double temp, Size size) {
    final frac = ((temp - kMinTemp) / (kMaxTemp - kMinTemp)).clamp(0.0, 1.0);
    return size.height - frac * size.height;
  }

  @override
  bool shouldRepaint(_CurvePainter old) => true;
}
