import 'dart:async';

import 'package:flutter/material.dart';

import '../models.dart';
import '../theme.dart';
import '../util.dart';
import 'climate_bar.dart';
import '../haptics.dart';

/// The temperature hero: a big current-value readout, a stepped slider
/// (16–30 in 0.5° steps), and − / + buttons on each side for single steps.
///
/// Stateful so an in-flight drag isn't yanked when a state poll arrives: the
/// slider follows the finger locally and only reports on release; the steppers
/// act on the committed [value].
class TempControl extends StatefulWidget {
  const TempControl({
    super.key,
    required this.value,
    required this.accent,
    required this.unit,
    required this.onChanged,
    this.indoor,
    this.outdoor,
    this.enabled = true,
  });

  final double value;
  final double? indoor;
  final double? outdoor;
  final Color accent;
  final String unit;
  final ValueChanged<double> onChanged;
  final bool enabled;

  @override
  State<TempControl> createState() => _TempControlState();
}

class _TempControlState extends State<TempControl> {
  double? _dragging;
  Timer? _repeat;

  double get _shown => _dragging ?? widget.value;

  void _step(double delta) {
    if (!widget.enabled) return;
    final next = snapHalf((widget.value + delta).clamp(kMinTemp, kMaxTemp));
    if (next != widget.value) {
      Haptics.tick();
      widget.onChanged(next);
    }
  }

  // Press and hold − / + to keep stepping, so 16 to 30 is one hold instead of
  // 28 taps -- which matters most to someone for whom each tap is effort.
  // Like the slider, the number moves locally and is sent once, on release,
  // rather than as a command per step.
  void _holdStart(double delta) {
    if (!widget.enabled) return;
    _repeat?.cancel();
    void tick() {
      final from = _dragging ?? widget.value;
      final next = snapHalf((from + delta).clamp(kMinTemp, kMaxTemp));
      if (next != from) {
        Haptics.tick();
        setState(() => _dragging = next);
      }
    }

    tick();
    _repeat = Timer.periodic(const Duration(milliseconds: 180), (_) => tick());
  }

  void _holdEnd() {
    _repeat?.cancel();
    _repeat = null;
    final held = _dragging;
    setState(() => _dragging = null);
    if (held != null && held != widget.value) widget.onChanged(held);
  }

  @override
  void dispose() {
    _repeat?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final accent = widget.accent;
    final shown = _shown.clamp(kMinTemp, kMaxTemp);

    // Sit above centre rather than dead-centre in the slack: the flap pill
    // freed vertical space, and pure centring spent half of it above the
    // readout, dropping the number lower than it used to sit. The fractional
    // bias scales with the screen instead of hard-coding an offset.
    return Align(
      alignment: const Alignment(0, -0.4),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Big readout. Read as "Target temperature, 23.5 °C" rather than a
          // bare number, and a live region, so a change -- from the buttons,
          // or from another phone -- is spoken without moving focus.
          Semantics(
            label: 'Target temperature',
            value: fmtTemp(shown, widget.unit),
            liveRegion: true,
            excludeSemantics: true,
            child: FittedBox(
              child: Text(
                fmtTemp(shown, widget.unit, showUnit: false),
                style: TextStyle(
                  fontSize: 88,
                  fontWeight: FontWeight.w300,
                  height: 1.0,
                  color: widget.enabled
                      ? scheme.onSurface
                      : scheme.onSurfaceVariant,
                  letterSpacing: -2,
                ),
              ),
            ),
          ),
          const SizedBox(height: 2),
          if (widget.indoor != null || widget.outdoor != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: ClimateBar(
                indoor: widget.indoor,
                outdoor: widget.outdoor,
                target: shown.toDouble(),
                accent: accent,
                unit: widget.unit,
              ),
            )
          else
            Text(
              'target',
              style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 14),
            ),
          const SizedBox(height: 10),
          Row(
            children: [
              _StepButton(
                icon: Icons.remove,
                label: 'Lower the target temperature',
                accent: accent,
                onTap: widget.enabled ? () => _step(-0.5) : null,
                onHoldStart: () => _holdStart(-0.5),
                onHoldEnd: _holdEnd,
              ),
              Expanded(
                child: SliderTheme(
                  data: SliderThemeData(
                    trackHeight: 8,
                    activeTrackColor: accent,
                    inactiveTrackColor: accent.withValues(alpha: 0.18),
                    thumbColor: accent,
                    overlayColor: accent.withValues(alpha: 0.15),
                    thumbShape: const RoundSliderThumbShape(
                      enabledThumbRadius: 12,
                    ),
                    showValueIndicator: ShowValueIndicator.never,
                  ),
                  child: Slider(
                    // Named, and read in degrees: it said "57 percent". No
                    // value bubble shows the label (showValueIndicator: never).
                    label: 'Target temperature',
                    min: kMinTemp,
                    max: kMaxTemp,
                    divisions: ((kMaxTemp - kMinTemp) * 2).round(),
                    value: shown.toDouble(),
                    semanticFormatterCallback: (v) =>
                        fmtTemp(snapHalf(v), widget.unit),
                    onChanged: widget.enabled
                        ? (v) {
                            final snapped = snapHalf(v);
                            // Tick only when the value actually moves a
                            // notch, not on every pixel of the drag.
                            if (snapped != _dragging) Haptics.tick();
                            setState(() => _dragging = snapped);
                          }
                        : null,
                    onChangeEnd: (v) {
                      final snapped = snapHalf(v);
                      setState(() => _dragging = null);
                      if (snapped != widget.value) widget.onChanged(snapped);
                    },
                  ),
                ),
              ),
              _StepButton(
                icon: Icons.add,
                label: 'Raise the target temperature',
                accent: accent,
                onTap: widget.enabled ? () => _step(0.5) : null,
                onHoldStart: () => _holdStart(0.5),
                onHoldEnd: _holdEnd,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _StepButton extends StatelessWidget {
  const _StepButton({
    required this.icon,
    required this.label,
    required this.accent,
    this.onTap,
    this.onHoldStart,
    this.onHoldEnd,
  });
  final IconData icon;
  final String label;
  final Color accent;
  final VoidCallback? onTap;
  final VoidCallback? onHoldStart;
  final VoidCallback? onHoldEnd;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    // A named button: it was an unlabelled icon, "Unlabelled, double-tap to
    // activate" to TalkBack, and unreachable by name for Voice Access.
    return Semantics(
      button: true,
      enabled: onTap != null,
      label: label,
      onTap: onTap,
      excludeSemantics: true,
      child: GestureDetector(
        onLongPressStart: onTap == null || onHoldStart == null
            ? null
            : (_) => onHoldStart!(),
        onLongPressEnd: onHoldEnd == null ? null : (_) => onHoldEnd!(),
        onLongPressCancel: onHoldEnd,
        child: SizedBox(
          width: 52,
          height: 52,
          child: Material(
            color: onTap == null
                ? scheme.surfaceContainerHighest.withValues(alpha: 0.4)
                : accent.withValues(alpha: 0.16),
            shape: const CircleBorder(),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: onTap,
              child: Icon(
                icon,
                color: onTap == null
                    ? scheme.onSurfaceVariant
                    : readableAccent(
                        accent,
                        scheme,
                        on: layeredOnSurface(scheme, [
                          accent.withValues(alpha: 0.16),
                        ]),
                      ),
                size: 26,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
