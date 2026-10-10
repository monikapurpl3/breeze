import 'package:flutter/material.dart';

import '../models.dart';
import '../util.dart';

/// The setpoint a curve asks for at [minute] of the day (0–1439): linear
/// between points, and cyclic over the 24 hours, the way the server's
/// scheduler interpolates it -- so a 22:00 point leads into a 02:00 one
/// through midnight rather than stopping at the edge of the day.
double curveAt(List<CurvePoint> points, int minute) {
  if (points.isEmpty) return (kMinTemp + kMaxTemp) / 2;
  final pts = [...points]..sort((a, b) => minutesOf(a.time).compareTo(minutesOf(b.time)));
  if (pts.length == 1) return pts.first.temperature;
  CurvePoint? before, after;
  for (final p in pts) {
    if (minutesOf(p.time) <= minute) before = p;
  }
  for (final p in pts) {
    if (minutesOf(p.time) > minute) {
      after = p;
      break;
    }
  }
  before ??= pts.last; // before the first point: the last one, yesterday
  after ??= pts.first; // after the last point: the first one, tomorrow
  var from = minutesOf(before.time);
  var to = minutesOf(after.time);
  var at = minute;
  if (to <= from) to += 1440; // the stretch crosses midnight
  if (at < from) at += 1440;
  final span = to - from;
  if (span == 0) return before.temperature;
  final f = (at - from) / span;
  return before.temperature + (after.temperature - before.temperature) * f;
}

/// A read-only 24-hour picture of a temperature curve: the setpoint over the
/// day, through midnight, with each point marked.
///
/// [compact] is the sparkline for the programs list: no grid, no labels.
class CurveChart extends StatelessWidget {
  const CurveChart({
    super.key,
    required this.points,
    required this.accent,
    this.height = 180,
    this.compact = false,
  });

  final List<CurvePoint> points;
  final Color accent;
  final double height;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final temps = points.map((p) => p.temperature).toList();
    final lo = temps.isEmpty ? kMinTemp : temps.reduce((a, b) => a < b ? a : b);
    final hi = temps.isEmpty ? kMaxTemp : temps.reduce((a, b) => a > b ? a : b);
    return Semantics(
      // The points are listed (and editable) below the chart; this is the
      // picture's one-line gist.
      label: points.isEmpty
          ? 'Temperature curve, no points'
          : 'Temperature curve, ${points.length} points, from '
              '${lo.toStringAsFixed(1)} to ${hi.toStringAsFixed(1)} degrees',
      excludeSemantics: true,
      child: SizedBox(
        height: height,
        width: double.infinity,
        child: CustomPaint(
          painter: _CurvePainter(
            points: points,
            accent: accent,
            grid: scheme.outlineVariant.withValues(alpha: 0.6),
            label: scheme.onSurfaceVariant,
            surface: scheme.surface,
            compact: compact,
            font: DefaultTextStyle.of(context).style.fontFamily,
          ),
        ),
      ),
    );
  }
}

class _CurvePainter extends CustomPainter {
  _CurvePainter({
    required this.points,
    required this.accent,
    required this.grid,
    required this.label,
    required this.surface,
    required this.compact,
    required this.font,
  });

  final List<CurvePoint> points;
  final Color accent;
  final Color grid;
  final Color label;
  final Color surface;
  final bool compact;
  final String? font;

  // Room for the temperature labels on the left and the hours underneath.
  double get _left => compact ? 0 : 30;
  double get _bottom => compact ? 0 : 18;
  double get _top => compact ? 2 : 8;

  /// The vertical range: the points' own span with a little air, never less
  /// than four degrees, so a nearly flat curve doesn't look like a cliff.
  (double, double) _range() {
    if (points.isEmpty) return (kMinTemp, kMaxTemp);
    var lo = points.map((p) => p.temperature).reduce((a, b) => a < b ? a : b);
    var hi = points.map((p) => p.temperature).reduce((a, b) => a > b ? a : b);
    final mid = (lo + hi) / 2;
    if (hi - lo < 4) {
      lo = mid - 2;
      hi = mid + 2;
    }
    lo = (lo - 1).floorToDouble().clamp(kMinTemp - 2, kMaxTemp);
    hi = (hi + 1).ceilToDouble().clamp(kMinTemp, kMaxTemp + 2);
    return (lo, hi);
  }

  @override
  void paint(Canvas canvas, Size size) {
    final (lo, hi) = _range();
    final w = size.width - _left;
    final h = size.height - _top - _bottom;
    double x(int minute) => _left + w * minute / 1440;
    double y(double t) => _top + h * (1 - (t - lo) / (hi - lo));

    if (!compact) {
      final gridPaint = Paint()
        ..color = grid
        ..strokeWidth = 1;
      // Temperatures: bottom, middle, top.
      for (final t in [lo, (lo + hi) / 2, hi]) {
        canvas.drawLine(Offset(_left, y(t)), Offset(size.width, y(t)), gridPaint);
        _text(canvas, '${t.toStringAsFixed(0)}°', Offset(0, y(t) - 7));
      }
      // Hours: every six, with the day's ends.
      for (final hour in [0, 6, 12, 18, 24]) {
        final px = x(hour * 60);
        canvas.drawLine(Offset(px, _top), Offset(px, _top + h), gridPaint..strokeWidth = 0.5);
        final s = hour.toString().padLeft(2, '0');
        _text(canvas, s, Offset(px - (hour == 24 ? 14 : hour == 0 ? 0 : 7), size.height - 14));
      }
    }
    if (points.isEmpty) return;

    // The line, sampled every ten minutes through the whole day.
    final path = Path();
    for (var m = 0; m <= 1440; m += 10) {
      final p = Offset(x(m), y(curveAt(points, m % 1440)));
      m == 0 ? path.moveTo(p.dx, p.dy) : path.lineTo(p.dx, p.dy);
    }
    final fill = Path.from(path)
      ..lineTo(x(1440), _top + h)
      ..lineTo(x(0), _top + h)
      ..close();
    canvas.drawPath(
      fill,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [accent.withValues(alpha: 0.30), accent.withValues(alpha: 0.02)],
        ).createShader(Rect.fromLTWH(0, _top, size.width, h)),
    );
    canvas.drawPath(
      path,
      Paint()
        ..color = accent
        ..style = PaintingStyle.stroke
        ..strokeWidth = compact ? 2 : 2.5
        ..strokeJoin = StrokeJoin.round,
    );
    if (compact) return;
    for (final p in points) {
      final c = Offset(x(minutesOf(p.time)), y(p.temperature));
      canvas.drawCircle(c, 6, Paint()..color = surface);
      canvas.drawCircle(c, 4.5, Paint()..color = accent);
    }
  }

  void _text(Canvas canvas, String s, Offset at) {
    final tp = TextPainter(
      text: TextSpan(text: s, style: TextStyle(color: label, fontSize: 10.5, fontFamily: font)),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, at);
  }

  @override
  // Points are edited in place, so the list is the same object before and
  // after a change: comparing it would skip the redraw.
  bool shouldRepaint(covariant _CurvePainter old) => true;
}
