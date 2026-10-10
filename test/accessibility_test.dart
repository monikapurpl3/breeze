// What TalkBack, Switch Access and Voice Access get from the unit screen's
// controls, pinned so it cannot quietly regress.
//
// An audit for a blind user found that the selected mode, the flap halves and
// fan Auto never said whether they were on; the temperature slider read as
// "57 percent"; power, eco and turbo each came out as two nodes, one of them
// unlabelled; and accent-coloured text fell to 1.6:1 contrast in the light
// theme. Each of those is a test here, in both themes.

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:breeze/src/models.dart';
import 'package:breeze/src/widgets/big_toggle.dart';
import 'package:breeze/src/widgets/fan_control.dart';
import 'package:breeze/src/widgets/flap_control.dart';
import 'package:breeze/src/widgets/mode_selector.dart';
import 'package:breeze/src/widgets/power_switch.dart';
import 'package:breeze/src/widgets/temp_control.dart';

// The node the slider itself makes -- getSemantics on the widget finds a wrapper
// above it, with no label.
SemanticsNode _slider(WidgetTester tester) => find.semantics
    .byPredicate((node) => node.getSemanticsData().flagsCollection.isSlider)
    .evaluate()
    .single;

Widget _host(Widget child, Brightness brightness) => MaterialApp(
  theme: ThemeData(
    colorSchemeSeed: const Color(0xFF00897B),
    brightness: brightness,
  ),
  home: Scaffold(
    body: Center(
      child: Padding(padding: const EdgeInsets.all(24), child: child),
    ),
  ),
);

void main() {
  for (final brightness in Brightness.values) {
    group('${brightness.name} theme', () {
      testWidgets('the selected mode says it is selected, the others not', (
        tester,
      ) async {
        final handle = tester.ensureSemantics();
        await tester.pumpWidget(
          _host(ModeSelector(value: 'COOL', onChanged: (_) {}), brightness),
        );
        expect(
          tester.getSemantics(find.text('cool')),
          isSemantics(
            isSelected: true,
            isButton: true,
            isInMutuallyExclusiveGroup: true,
            hasTapAction: true,
          ),
        );
        expect(
          tester.getSemantics(find.text('heat')),
          isSemantics(isSelected: false, isButton: true, hasTapAction: true),
        );
        await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
        await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
        handle.dispose();
      });

      // Each mode has its own accent, so each selected label is its own
      // colour on its own tint -- check them all, not just one.
      for (final mode in kModes) {
        testWidgets('the selected $mode label can be read', (tester) async {
          final handle = tester.ensureSemantics();
          await tester.pumpWidget(
            _host(ModeSelector(value: mode, onChanged: (_) {}), brightness),
          );
          await expectLater(tester, meetsGuideline(textContrastGuideline));
          handle.dispose();
        });
      }

      testWidgets('each flap half says whether it is on', (tester) async {
        final handle = tester.ensureSemantics();
        await tester.pumpWidget(
          _host(
            FlapControl(
              value: 'VERTICAL',
              accent: const Color(0xFFE0B93A),
              onChanged: (_) {},
            ),
            brightness,
          ),
        );
        expect(
          tester.getSemantics(find.text('Vertical flap')),
          isSemantics(
            hasToggledState: true,
            isToggled: true,
            hasTapAction: true,
          ),
        );
        expect(
          tester.getSemantics(find.text('Horizontal flap')),
          isSemantics(
            hasToggledState: true,
            isToggled: false,
            hasTapAction: true,
          ),
        );
        await expectLater(tester, meetsGuideline(textContrastGuideline));
        handle.dispose();
      });

      testWidgets(
        'fan: a named slider read in words, and Auto says it is chosen',
        (tester) async {
          final handle = tester.ensureSemantics();
          await tester.pumpWidget(
            _host(
              FanControl(
                value: 102,
                accent: const Color(0xFF9D7CD8),
                onChanged: (_) {},
              ),
              brightness,
            ),
          );
          final slider = _slider(tester);
          expect(slider.label, contains('Fan speed'));
          expect(slider.value, isNot(contains('%')));
          expect(
            tester.getSemantics(find.text('Auto')),
            isSemantics(isSelected: true, isButton: true, hasTapAction: true),
          );
          await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
          await expectLater(tester, meetsGuideline(textContrastGuideline));
          handle.dispose();
        },
      );

      testWidgets('temperature: degrees, not percent, and named step buttons', (
        tester,
      ) async {
        final handle = tester.ensureSemantics();
        await tester.pumpWidget(
          _host(
            TempControl(
              value: 23.5,
              accent: const Color(0xFFF0954B),
              unit: 'C',
              onChanged: (_) {},
            ),
            brightness,
          ),
        );
        final slider = _slider(tester);
        expect(slider.label, contains('Target temperature'));
        expect(slider.value, contains('23.5'));
        expect(slider.value, isNot(contains('%')));
        expect(
          find.bySemanticsLabel(RegExp('Lower the target temperature')),
          findsOneWidget,
        );
        expect(
          find.bySemanticsLabel(RegExp('Raise the target temperature')),
          findsOneWidget,
        );
        await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
        await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
        handle.dispose();
      });

      testWidgets('power is one switch, named, with its state', (tester) async {
        final handle = tester.ensureSemantics();
        await tester.pumpWidget(
          _host(PowerSwitch(on: true, onChanged: (_) {}), brightness),
        );
        final powers = find.bySemanticsLabel('Power');
        expect(powers, findsOneWidget);
        expect(
          tester.getSemantics(powers),
          isSemantics(
            hasToggledState: true,
            isToggled: true,
            hasTapAction: true,
          ),
        );
        // And nothing else that can be activated without a name.
        await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
        handle.dispose();
      });

      testWidgets('eco is one switch, named, with its state', (tester) async {
        final handle = tester.ensureSemantics();
        await tester.pumpWidget(
          _host(
            BigToggle(
              label: 'Eco',
              icon: Icons.eco,
              value: false,
              accent: const Color(0xFF4CAF50),
              onChanged: (_) {},
            ),
            brightness,
          ),
        );
        final ecos = find.bySemanticsLabel('Eco');
        expect(ecos, findsOneWidget);
        expect(
          tester.getSemantics(ecos),
          isSemantics(
            hasToggledState: true,
            isToggled: false,
            hasTapAction: true,
          ),
        );
        await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
        await expectLater(tester, meetsGuideline(textContrastGuideline));
        handle.dispose();
      });

      testWidgets('an eco that is on can be read', (tester) async {
        final handle = tester.ensureSemantics();
        await tester.pumpWidget(
          _host(
            BigToggle(
              label: 'Eco',
              icon: Icons.eco,
              value: true,
              accent: const Color(0xFF4CAF50),
              onChanged: (_) {},
            ),
            brightness,
          ),
        );
        expect(
          tester.getSemantics(find.bySemanticsLabel('Eco')),
          isSemantics(hasToggledState: true, isToggled: true),
        );
        await expectLater(tester, meetsGuideline(textContrastGuideline));
        handle.dispose();
      });
    });
  }
}
