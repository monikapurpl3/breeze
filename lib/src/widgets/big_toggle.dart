import 'package:flutter/material.dart';

/// A large, colourful on/off control for the main screen (eco, turbo, …).
/// The whole surface is tappable; it fills with a light tint of [accent] when
/// on, and carries a real Switch as the affordance. Deliberately big.
class BigToggle extends StatelessWidget {
  const BigToggle({
    super.key,
    required this.label,
    required this.icon,
    required this.value,
    required this.accent,
    required this.onChanged,
    this.enabled = true,
  });

  final String label;
  final IconData icon;
  final bool value;
  final Color accent;
  final ValueChanged<bool> onChanged;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final on = value && enabled;
    final fg = !enabled
        ? scheme.onSurfaceVariant.withValues(alpha: 0.4)
        : (on ? accent : scheme.onSurfaceVariant);

    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOut,
      decoration: BoxDecoration(
        color: on
            ? accent.withValues(alpha: 0.16)
            : scheme.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: on ? accent.withValues(alpha: 0.7) : Colors.transparent,
          width: 1.5,
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(22),
          onTap: enabled ? () => onChanged(!value) : null,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 10, 12),
            child: Row(
              children: [
                Icon(icon, color: fg, size: 26),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    label,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: fg,
                    ),
                  ),
                ),
                Switch(
                  value: value,
                  activeThumbColor: accent,
                  onChanged: enabled ? onChanged : null,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
