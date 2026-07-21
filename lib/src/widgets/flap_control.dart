import 'package:flutter/material.dart';

/// Flap (swing) control: an on/off switch, and — when on — a three-stop
/// slider whose left position is up/down only (VERTICAL), middle is BOTH, and
/// right is left/right only (HORIZONTAL). Off is swing OFF.
class FlapControl extends StatefulWidget {
  const FlapControl({
    super.key,
    required this.value, // OFF / VERTICAL / HORIZONTAL / BOTH
    required this.accent,
    required this.onChanged,
    this.enabled = true,
  });

  final String value;
  final Color accent;
  final ValueChanged<String> onChanged;
  final bool enabled;

  @override
  State<FlapControl> createState() => _FlapControlState();
}

class _FlapControlState extends State<FlapControl> {
  static const _positions = ['VERTICAL', 'BOTH', 'HORIZONTAL'];
  int? _dragIdx;

  bool get _on => widget.value != 'OFF';

  int get _committedIdx {
    final i = _positions.indexOf(widget.value);
    return i < 0 ? 1 : i; // default BOTH
  }

  int get _shownIdx => _dragIdx ?? _committedIdx;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final accent = widget.accent;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.swap_vert, size: 20, color: scheme.onSurfaceVariant),
            const SizedBox(width: 8),
            Text('Flap', style: TextStyle(fontWeight: FontWeight.w600, color: scheme.onSurface)),
            const Spacer(),
            Switch(
              value: _on,
              activeThumbColor: accent,
              onChanged: widget.enabled
                  // On → resume the middle (BOTH); Off → OFF.
                  ? (v) => widget.onChanged(v ? 'BOTH' : 'OFF')
                  : null,
            ),
          ],
        ),
        AnimatedOpacity(
          duration: const Duration(milliseconds: 150),
          opacity: _on ? 1 : 0.35,
          child: IgnorePointer(
            ignoring: !_on || !widget.enabled,
            child: Column(
              children: [
                SliderTheme(
                  data: SliderThemeData(
                    trackHeight: 6,
                    activeTrackColor: accent,
                    inactiveTrackColor: accent.withValues(alpha: 0.18),
                    thumbColor: accent,
                    overlayColor: accent.withValues(alpha: 0.15),
                    thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 10),
                  ),
                  child: Slider(
                    min: 0,
                    max: 2,
                    divisions: 2,
                    value: _shownIdx.toDouble(),
                    onChanged: (v) => setState(() => _dragIdx = v.round()),
                    onChangeEnd: (v) {
                      final idx = v.round();
                      setState(() => _dragIdx = null);
                      widget.onChanged(_positions[idx]);
                    },
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      _lbl(context, Icons.height, 'Up/Down'),
                      _lbl(context, Icons.open_in_full, 'Both'),
                      _lbl(context, Icons.swap_horiz, 'Left/Right'),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _lbl(BuildContext context, IconData icon, String text) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 15, color: scheme.onSurfaceVariant),
        Text(text, style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant)),
      ],
    );
  }
}
