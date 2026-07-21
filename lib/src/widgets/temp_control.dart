import 'package:flutter/material.dart';

import '../models.dart';
import '../util.dart';

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
    this.enabled = true,
  });

  final double value;
  final double? indoor;
  final Color accent;
  final String unit;
  final ValueChanged<double> onChanged;
  final bool enabled;

  @override
  State<TempControl> createState() => _TempControlState();
}

class _TempControlState extends State<TempControl> {
  double? _dragging;

  double get _shown => _dragging ?? widget.value;

  void _step(double delta) {
    if (!widget.enabled) return;
    final next = snapHalf((widget.value + delta).clamp(kMinTemp, kMaxTemp));
    if (next != widget.value) widget.onChanged(next);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final accent = widget.accent;
    final shown = _shown.clamp(kMinTemp, kMaxTemp);

    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        // Big readout.
        FittedBox(
          child: Text(
            fmtTemp(shown, widget.unit, showUnit: false),
            style: TextStyle(
              fontSize: 88,
              fontWeight: FontWeight.w300,
              height: 1.0,
              color: widget.enabled ? scheme.onSurface : scheme.onSurfaceVariant,
              letterSpacing: -2,
            ),
          ),
        ),
        const SizedBox(height: 2),
        if (widget.indoor != null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Row(
              children: [
                Text(
                  'indoor ${fmtTemp(widget.indoor!, widget.unit)}',
                  style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 14),
                ),
                const SizedBox(width: 12),
                Expanded(child: _IndoorBar(indoor: widget.indoor!, accent: accent)),
              ],
            ),
          )
        else
          Text('target', style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 14)),
        const SizedBox(height: 10),
        Row(
          children: [
            _StepButton(
              icon: Icons.remove,
              accent: accent,
              onTap: widget.enabled ? () => _step(-0.5) : null,
            ),
            Expanded(
              child: SliderTheme(
                data: SliderThemeData(
                  trackHeight: 8,
                  activeTrackColor: accent,
                  inactiveTrackColor: accent.withValues(alpha: 0.18),
                  thumbColor: accent,
                  overlayColor: accent.withValues(alpha: 0.15),
                  thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 12),
                  showValueIndicator: ShowValueIndicator.never,
                ),
                child: Slider(
                  min: kMinTemp,
                  max: kMaxTemp,
                  divisions: ((kMaxTemp - kMinTemp) * 2).round(),
                  value: shown.toDouble(),
                  onChanged: widget.enabled
                      ? (v) => setState(() => _dragging = snapHalf(v))
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
              accent: accent,
              onTap: widget.enabled ? () => _step(0.5) : null,
            ),
          ],
        ),
      ],
    );
  }
}

/// A slim rounded bar showing where the indoor temperature sits in a typical
/// room range (10–35 °C), filled in the current mode's accent colour.
class _IndoorBar extends StatelessWidget {
  const _IndoorBar({required this.indoor, required this.accent});
  final double indoor;
  final Color accent;

  static const _lo = 10.0;
  static const _hi = 35.0;

  @override
  Widget build(BuildContext context) {
    final frac = ((indoor - _lo) / (_hi - _lo)).clamp(0.0, 1.0);
    return ClipRRect(
      borderRadius: BorderRadius.circular(5),
      child: Container(
        height: 8,
        color: accent.withValues(alpha: 0.16),
        child: FractionallySizedBox(
          alignment: Alignment.centerLeft,
          widthFactor: frac,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: accent,
              borderRadius: BorderRadius.circular(5),
            ),
          ),
        ),
      ),
    );
  }
}

class _StepButton extends StatelessWidget {
  const _StepButton({required this.icon, required this.accent, this.onTap});
  final IconData icon;
  final Color accent;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
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
            color: onTap == null ? scheme.onSurfaceVariant : accent,
            size: 26,
          ),
        ),
      ),
    );
  }
}
