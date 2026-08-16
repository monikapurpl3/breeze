// The climate bar has one rule and a lot of ways for a sensor to lie to it.
// The rule is easy to eyeball; the lies are not, so they're all pinned here.

import 'package:flutter_test/flutter_test.dart';

import 'package:breeze/src/widgets/climate_bar.dart';

void main() {
  group('the rule: warmest sets the scale, warmer of the rest is lighter', () {
    test('cooling — outdoor hottest, target coolest', () {
      final m = ClimateBarModel.from(indoor: 27, outdoor: 33, target: 24);
      expect(m.usable, isTrue);
      expect(m.floor, 0);
      expect(m.max, 33);          // outdoor tops the scale
      expect(m.lighter, 27);      // indoor is the warmer of the remaining two
      expect(m.darker, 24);       // target sits on top, darker
    });

    test('heating — target hottest, outdoor coldest', () {
      final m = ClimateBarModel.from(indoor: 20, outdoor: 5, target: 23);
      expect(m.max, 23);          // target tops the scale
      expect(m.lighter, 20);      // indoor again the warmer of the pair
      expect(m.darker, 5);        // outdoor on top, darker
    });

    test('indoor below target swaps which one is lighter', () {
      final m = ClimateBarModel.from(indoor: 22, outdoor: 33, target: 25);
      expect(m.max, 33);
      expect(m.lighter, 25);      // the target is now the warmer of the pair
      expect(m.darker, 22);
    });
  });

  group('fractions', () {
    test('scale from the floor to the warmest reading', () {
      final m = ClimateBarModel.from(indoor: 27, outdoor: 33, target: 24);
      expect(m.fractionFor(0), 0);
      expect(m.fractionFor(33), 1);
      expect(m.fractionFor(27), closeTo(27 / 33, 1e-9));
    });

    test('a reading beyond the scale is clamped, never negative or >1', () {
      final m = ClimateBarModel.from(indoor: 20, outdoor: 5, target: 23);
      expect(m.fractionFor(-100), 0);
      expect(m.fractionFor(999), 1);
    });
  });

  group('failsafes', () {
    test('a freezing outdoor reading drops the floor below zero', () {
      // With a hard 0 floor this clamps to nothing and reads as a dead sensor.
      final m = ClimateBarModel.from(indoor: 21, outdoor: -8.4, target: 23);
      expect(m.floor, -9);        // floored, so the reading is inside the scale
      expect(m.fractionFor(-8.4), greaterThan(0));
      expect(m.max, 23);
    });

    test('identical readings still produce a drawable scale', () {
      final m = ClimateBarModel.from(indoor: 22, outdoor: 22, target: 22);
      expect(m.usable, isTrue);
      expect(m.max - m.floor, greaterThanOrEqualTo(1.0));  // no divide-by-zero
      expect(m.fractionFor(22).isFinite, isTrue);
    });

    test('missing outdoor falls back to a two-value bar', () {
      final m = ClimateBarModel.from(indoor: 27, outdoor: null, target: 24);
      expect(m.usable, isTrue);
      expect(m.max, 27);          // indoor tops the scale
      expect(m.darker, 24);       // the single fill is the target, full strength
      expect(m.lighter, isNull);  // no pair, so no pale layer beneath
    });

    test('a single reading is not a relationship — nothing to draw', () {
      expect(ClimateBarModel.from(indoor: 27).usable, isFalse);
      expect(ClimateBarModel.from(outdoor: 33).usable, isFalse);
      expect(ClimateBarModel.from().usable, isFalse);
    });

    test('sentinel readings from a unit with no outdoor probe are ignored', () {
      for (final junk in [255.0, -3000.0, 1e9, 100.0]) {
        expect(sanitiseTemp(junk), isNull, reason: '$junk should be rejected');
        final m = ClimateBarModel.from(indoor: 27, outdoor: junk, target: 24);
        expect(m.max, 27, reason: '$junk must not stretch the scale');
      }
    });

    test('NaN and infinity are treated as missing', () {
      expect(sanitiseTemp(double.nan), isNull);
      expect(sanitiseTemp(double.infinity), isNull);
      expect(sanitiseTemp(double.negativeInfinity), isNull);
      final m = ClimateBarModel.from(indoor: double.nan, outdoor: 33, target: 24);
      expect(m.max, 33);
      expect(m.darker, 24);
      expect(m.lighter, isNull);
    });

    test('plausible extremes are kept — this is a heatwave, not a fault', () {
      expect(sanitiseTemp(45), 45);     // a hot roof-mounted outdoor unit
      expect(sanitiseTemp(-30), -30);   // a genuinely cold winter
      expect(sanitiseTemp(0), 0);       // freezing is a real temperature
    });

    test('every reading garbage: nothing usable, and no exception', () {
      final m = ClimateBarModel.from(
          indoor: double.nan, outdoor: 999, target: double.negativeInfinity);
      expect(m.usable, isFalse);
      expect(m.fractionFor(20).isFinite, isTrue);  // still safe to call
    });
  });
}
