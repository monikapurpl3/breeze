import 'package:flutter/material.dart';

/// Power control: a large Material 3 switch instead of a round icon button, so
/// the on/off state is unmistakable at a glance and matches the mental model of
/// a physical rocker. **Faintly red when off, faintly green when on** — the
/// tracks are low-alpha so the switch reads as a status light without shouting
/// over the mode-tinted page, and the thumb carries the power glyph.
///
/// The colours are deliberately fixed (not mode-accent) — power is the one
/// control whose meaning must never shift with the palette.
class PowerSwitch extends StatelessWidget {
  const PowerSwitch({
    super.key,
    required this.on,
    required this.onChanged,
    this.enabled = true,
  });

  final bool on;
  final ValueChanged<bool> onChanged;
  final bool enabled;

  static const _green = Color(0xFF4CAF50);
  static const _red = Color(0xFFE53935);

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Semantics(
      label: 'Power',
      toggled: on,
      child: Transform.scale(
        scale: 1.2, // "big" without breaking the header row's height
        child: Switch(
          value: on,
          onChanged: enabled ? onChanged : null,
          // Thumb: solid colour so it stays legible on the faint track.
          thumbColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.disabled)) {
              return scheme.onSurfaceVariant.withValues(alpha: 0.4);
            }
            return states.contains(WidgetState.selected) ? _green : _red;
          }),
          // Track: the "faint" part — a tinted wash, not a saturated slab.
          trackColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.disabled)) {
              return scheme.surfaceContainerHighest.withValues(alpha: 0.4);
            }
            return states.contains(WidgetState.selected)
                ? _green.withValues(alpha: 0.22)
                : _red.withValues(alpha: 0.16);
          }),
          trackOutlineColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.disabled)) {
              return scheme.outlineVariant.withValues(alpha: 0.5);
            }
            return states.contains(WidgetState.selected)
                ? _green.withValues(alpha: 0.45)
                : _red.withValues(alpha: 0.40);
          }),
          trackOutlineWidth: const WidgetStatePropertyAll(1.5),
          thumbIcon: WidgetStateProperty.resolveWith(
            (states) => Icon(
              Icons.power_settings_new,
              color: states.contains(WidgetState.disabled)
                  ? scheme.surface.withValues(alpha: 0.7)
                  : Colors.white,
            ),
          ),
        ),
      ),
    );
  }
}
