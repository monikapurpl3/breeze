import 'dart:math' as math;
import 'package:flutter/material.dart';

import '../models.dart';
import '../util.dart';

/// The circular temperature gauge: a ring filled proportionally to the
/// target (16–30°) in the mode accent, with the indoor reading centered.
class Dial extends StatelessWidget {
  final double? indoor;
  final double target;
  final Color accent;
  final bool online;
  final String tempUnit;
  const Dial({
    super.key,
    required this.indoor,
    required this.target,
    required this.accent,
    required this.online,
    this.tempUnit = 'C',
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final frac = ((target - kMinTemp) / (kMaxTemp - kMinTemp)).clamp(0.0, 1.0);
    return SizedBox(
      width: 172,
      height: 172,
      child: CustomPaint(
        painter: _DialPainter(
          fraction: frac,
          accent: online ? accent : scheme.outline,
          track: scheme.surfaceContainerHighest,
        ),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                indoor == null ? '--°' : fmtTemp(indoor!, tempUnit, showUnit: false),
                style: Theme.of(context)
                    .textTheme
                    .displaySmall
                    ?.copyWith(fontWeight: FontWeight.w600),
              ),
              Text('indoor',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: scheme.onSurfaceVariant, letterSpacing: 1.2)),
              const SizedBox(height: 4),
              Text('target ${fmtTemp(target, tempUnit)}',
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(color: scheme.onSurfaceVariant)),
            ],
          ),
        ),
      ),
    );
  }
}

class _DialPainter extends CustomPainter {
  final double fraction;
  final Color accent;
  final Color track;
  _DialPainter({required this.fraction, required this.accent, required this.track});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 8;
    final trackPaint = Paint()
      ..color = track
      ..style = PaintingStyle.stroke
      ..strokeWidth = 9;
    final fillPaint = Paint()
      ..color = accent
      ..style = PaintingStyle.stroke
      ..strokeWidth = 9
      ..strokeCap = StrokeCap.round;
    canvas.drawCircle(center, radius, trackPaint);
    // start at top, sweep clockwise proportional to the target
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -math.pi / 2,
      2 * math.pi * fraction,
      false,
      fillPaint,
    );
  }

  @override
  bool shouldRepaint(_DialPainter old) =>
      old.fraction != fraction || old.accent != accent || old.track != track;
}
