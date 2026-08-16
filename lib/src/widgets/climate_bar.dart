// The indoor / outdoor / target bar.
//
// One rule covers every case, which is worth stating because the obvious
// description of this widget is three rules that can contradict each other:
//
//   * the WARMEST of the three temperatures sets the top of the scale — the
//     bar's full width is that value;
//   * the other two are drawn from the floor as overlapping fills: the warmer
//     of them lighter, the cooler darker and painted on top.
//
// Both of the cases this was asked for fall out of that:
//
//   cooling — outdoor 33, indoor 27, target 24
//     scale tops out at the outdoor reading; indoor is the lighter fill;
//     target is the darker fill over it.
//   heating — outdoor 5, indoor 20, target 23
//     scale tops out at the target; indoor is again the lighter fill; the
//     outdoor reading is the darker one on top.
//
// …and so does "if indoor is below target, the lightnesses swap": with indoor
// 22 and target 25 the warmer of the pair is now the target, so it takes the
// lighter shade. No special case needed — warmer is always lighter.
//
// The geometry is computed in Celsius regardless of the display unit; only the
// labels are converted, so a °F user gets identical proportions.

import 'package:flutter/material.dart';

import '../util.dart';

/// Readings outside this window are sensor nonsense, not weather.
///
/// Units without an outdoor probe don't always report null — they report a
/// sentinel, and a bar scaled to 255 °C (or -3000) would render as an empty
/// sliver with no hint as to why. Anything outside this is treated as missing.
const double kSaneMinC = -50.0;
const double kSaneMaxC = 80.0;

/// The smallest scale span we'll draw. Without it, three equal readings give
/// max == floor and every fraction becomes a division by zero.
const double _kMinSpan = 1.0;

/// A temperature that is present, finite, and physically plausible.
double? sanitiseTemp(double? value) {
  if (value == null) return null;
  if (!value.isFinite) return null;                 // NaN and ±infinity
  if (value < kSaneMinC || value > kSaneMaxC) return null;
  return value;
}

/// The geometry of the bar, worked out separately from any widget so the
/// awkward cases can be tested without pumping a frame.
@immutable
class ClimateBarModel {
  const ClimateBarModel({
    required this.floor,
    required this.max,
    required this.lighter,
    required this.darker,
    required this.usable,
  });

  /// Bottom of the scale — normally 0 °C, but extended downwards when
  /// something is below freezing, because a scale that starts at 0 would
  /// clamp a -8 °C outdoor reading to nothing and look like a broken sensor.
  final double floor;

  /// Top of the scale: the warmest of the readings we have.
  final double max;

  /// The warmer of the two remaining readings (drawn first, lighter).
  final double? lighter;

  /// The cooler of the two (drawn over the lighter, darker).
  final double? darker;

  /// False when there isn't enough real data to draw anything honest.
  final bool usable;

  static const ClimateBarModel empty = ClimateBarModel(
    floor: 0, max: 1, lighter: null, darker: null, usable: false,
  );

  /// Build from whatever the unit reported. Any of these may be null, absurd,
  /// or NaN; the result is either usable or explicitly not.
  factory ClimateBarModel.from({
    double? indoor,
    double? outdoor,
    double? target,
  }) {
    final values = <double>[
      for (final v in [sanitiseTemp(indoor), sanitiseTemp(outdoor), sanitiseTemp(target)]) ?v,
    ];
    // One reading can't express a relationship, so there's nothing to draw.
    if (values.length < 2) return empty;

    values.sort();
    final top = values.last;
    final rest = values.sublist(0, values.length - 1);

    // Floor at 0 °C normally; drop below only if a reading demands it.
    var floor = 0.0;
    if (values.first < floor) floor = values.first.floorToDouble();
    // A reading above 0 with everything bunched at the top still needs a span.
    var max = top;
    if (max - floor < _kMinSpan) max = floor + _kMinSpan;

    // rest is sorted ascending: last is the warmer (lighter), first the cooler.
    //
    // With only two readings there is no pair to distinguish, so the single
    // fill takes the strong colour rather than the pale one — a lone washed-out
    // bar looks like a rendering fault, and the light shade only earns its
    // meaning when something darker sits on top of it.
    final lighter = rest.length > 1 ? rest.last : null;
    final darker = rest.first;
    return ClimateBarModel(
      floor: floor,
      max: max,
      lighter: lighter,
      darker: darker,
      usable: true,
    );
  }

  /// Where a temperature sits along the bar, 0..1.
  double fractionFor(double celsius) {
    final span = max - floor;
    if (span <= 0) return 0;                        // belt and braces
    return ((celsius - floor) / span).clamp(0.0, 1.0);
  }
}

/// `I: 27.0 °C / O: 33.0 °C`, with the bar underneath.
class ClimateBar extends StatelessWidget {
  const ClimateBar({
    super.key,
    required this.indoor,
    required this.outdoor,
    required this.target,
    required this.accent,
    required this.unit,
  });

  final double? indoor;
  final double? outdoor;
  final double? target;
  final Color accent;
  final String unit;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final inC = sanitiseTemp(indoor);
    final outC = sanitiseTemp(outdoor);
    final model = ClimateBarModel.from(indoor: indoor, outdoor: outdoor, target: target);

    // The reading line stays even when the bar can't be drawn — knowing it's
    // 27 inside is useful on its own.
    final parts = <String>[
      if (inC != null) 'I: ${fmtTemp(inC, unit)}',
      if (outC != null) 'O: ${fmtTemp(outC, unit)}',
    ];
    if (parts.isEmpty) return const SizedBox.shrink();

    return Semantics(
      label: [
        if (inC != null) 'indoor ${fmtTemp(inC, unit)}',
        if (outC != null) 'outdoor ${fmtTemp(outC, unit)}',
        if (sanitiseTemp(target) != null) 'target ${fmtTemp(target!, unit)}',
      ].join(', '),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            parts.join('  /  '),
            style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 14),
          ),
          if (model.usable) ...[
            const SizedBox(height: 6),
            _Bar(model: model, accent: accent),
          ],
        ],
      ),
    );
  }
}

class _Bar extends StatelessWidget {
  const _Bar({required this.model, required this.accent});

  final ClimateBarModel model;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final lighter = model.lighter;
    final darker = model.darker;

    return ClipRRect(
      borderRadius: BorderRadius.circular(5),
      child: SizedBox(
        height: 8,
        child: Stack(
          children: [
            // The track itself is the warmest reading: full width == scale max.
            Positioned.fill(
              child: ColoredBox(color: accent.withValues(alpha: 0.14)),
            ),
            if (lighter != null)
              _Fill(fraction: model.fractionFor(lighter), color: accent.withValues(alpha: 0.45)),
            // Painted last so it sits on top of the lighter fill — which is
            // the whole point when the two values are close together.
            if (darker != null)
              _Fill(fraction: model.fractionFor(darker), color: accent),
          ],
        ),
      ),
    );
  }
}

class _Fill extends StatelessWidget {
  const _Fill({required this.fraction, required this.color});

  final double fraction;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: FractionallySizedBox(
        alignment: Alignment.centerLeft,
        widthFactor: fraction.clamp(0.0, 1.0),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(5),
          ),
        ),
      ),
    );
  }
}
