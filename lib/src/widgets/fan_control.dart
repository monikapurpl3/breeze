import 'package:flutter/material.dart';

/// Fan speed: a Low→High slider over the five manual steps (20/40/60/80/100),
/// which "detaches" to an Auto pill on the right. Picking Auto (fan_speed 102)
/// greys the slider; touching the slider re-engages manual control.
class FanControl extends StatefulWidget {
  const FanControl({
    super.key,
    required this.value,
    required this.accent,
    required this.onChanged,
    this.enabled = true,
  });

  final int value; // 20/40/60/80/100, or 102 = auto
  final Color accent;
  final ValueChanged<int> onChanged;
  final bool enabled;

  @override
  State<FanControl> createState() => _FanControlState();
}

class _FanControlState extends State<FanControl> {
  static const _steps = [20, 40, 60, 80, 100];
  int? _dragIdx;

  bool get _isAuto => widget.value == 102;

  int get _committedIdx {
    final i = _steps.indexOf(widget.value);
    return i < 0 ? 2 : i; // odd/unknown → middle
  }

  int get _shownIdx => _dragIdx ?? _committedIdx;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final accent = widget.accent;
    final auto = _isAuto;
    final sliderColor = auto
        ? scheme.onSurfaceVariant.withValues(alpha: 0.35)
        : accent;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.air, size: 20, color: scheme.onSurfaceVariant),
            const SizedBox(width: 8),
            Text('Fan', style: TextStyle(fontWeight: FontWeight.w600, color: scheme.onSurface)),
            const Spacer(),
            _AutoPill(
              active: auto,
              accent: accent,
              onTap: widget.enabled ? () => widget.onChanged(102) : null,
            ),
          ],
        ),
        Row(
          children: [
            Expanded(
              child: SliderTheme(
                data: SliderThemeData(
                  trackHeight: 6,
                  activeTrackColor: sliderColor,
                  inactiveTrackColor: sliderColor.withValues(alpha: 0.18),
                  thumbColor: sliderColor,
                  overlayColor: accent.withValues(alpha: 0.15),
                  thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 10),
                ),
                child: Slider(
                  min: 0,
                  max: 4,
                  divisions: 4,
                  value: _shownIdx.toDouble(),
                  onChanged: widget.enabled
                      ? (v) => setState(() => _dragIdx = v.round())
                      : null,
                  onChangeEnd: (v) {
                    final idx = v.round();
                    setState(() => _dragIdx = null);
                    widget.onChanged(_steps[idx]); // also clears auto
                  },
                ),
              ),
            ),
          ],
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Low', style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
              Text('High', style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
            ],
          ),
        ),
      ],
    );
  }
}

class _AutoPill extends StatelessWidget {
  const _AutoPill({required this.active, required this.accent, this.onTap});
  final bool active;
  final Color accent;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: active ? accent.withValues(alpha: 0.18) : scheme.surfaceContainerHighest.withValues(alpha: 0.5),
      shape: StadiumBorder(
        side: BorderSide(color: active ? accent : Colors.transparent, width: 1.5),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.auto_mode, size: 16, color: active ? accent : scheme.onSurfaceVariant),
              const SizedBox(width: 6),
              Text(
                'Auto',
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  color: active ? accent : scheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
