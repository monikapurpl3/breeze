import 'package:flutter/material.dart';
import '../haptics.dart';

/// Flap (swing) control: one big pill split into two independently-toggled
/// halves — **vertical** (up/down) and **horizontal** (left/right) — which is
/// exactly what the wire values mean: neither = `OFF`, one = `VERTICAL` /
/// `HORIZONTAL`, both = `BOTH`. A lit half is accent-filled, an unlit one stays
/// neutral, so the current swing reads at a glance with no slider to aim at.
///
/// Firmware silently ignores an axis the unit doesn't have (a unit with no
/// horizontal flap just won't move) — the server's `capabilities` endpoint is
/// the way to hide a half outright.
class FlapControl extends StatelessWidget {
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

  bool get _vertical => value == 'VERTICAL' || value == 'BOTH';
  bool get _horizontal => value == 'HORIZONTAL' || value == 'BOTH';

  /// Fold the two axes back into the single wire enum.
  static String _combine(bool vertical, bool horizontal) =>
      vertical && horizontal
      ? 'BOTH'
      : vertical
      ? 'VERTICAL'
      : horizontal
      ? 'HORIZONTAL'
      : 'OFF';

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    const radius = Radius.circular(34);

    return Opacity(
      opacity: enabled ? 1 : 0.4,
      child: Container(
        height: 68,
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHighest.withValues(alpha: 0.45),
          borderRadius: BorderRadius.circular(34),
        ),
        clipBehavior: Clip.antiAlias,
        child: Row(
          // stretch: each half must fill the pill's full height, so the accent
          // fill covers its side and the whole half is tappable (the default
          // centre alignment would shrink both to their content height).
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: _Half(
                icon: Icons.swap_vert,
                label: 'Vertical flap',
                on: _vertical,
                accent: accent,
                enabled: enabled,
                borderRadius: const BorderRadius.only(
                  topLeft: radius,
                  bottomLeft: radius,
                ),
                onTap: () => onChanged(_combine(!_vertical, _horizontal)),
              ),
            ),
            // Hairline seam so the two halves read as one pill, not two
            // buttons. Vertical margin insets it (stretch would otherwise run
            // it edge to edge).
            Container(
              width: 1,
              margin: const EdgeInsets.symmetric(vertical: 17),
              color: scheme.outlineVariant.withValues(alpha: 0.5),
            ),
            Expanded(
              child: _Half(
                icon: Icons.swap_horiz,
                label: 'Horizontal flap',
                on: _horizontal,
                accent: accent,
                enabled: enabled,
                borderRadius: const BorderRadius.only(
                  topRight: radius,
                  bottomRight: radius,
                ),
                onTap: () => onChanged(_combine(_vertical, !_horizontal)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Half extends StatelessWidget {
  const _Half({
    required this.icon,
    required this.label,
    required this.on,
    required this.accent,
    required this.enabled,
    required this.borderRadius,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool on;
  final Color accent;
  final bool enabled;
  final BorderRadius borderRadius;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final fg = on ? accent : scheme.onSurfaceVariant;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOut,
      decoration: BoxDecoration(
        color: on ? accent.withValues(alpha: 0.20) : Colors.transparent,
        borderRadius: borderRadius,
      ),
      child: InkWell(
        onTap: enabled
            ? () {
                Haptics.select();
                onTap();
              }
            : null,
        customBorder: RoundedRectangleBorder(borderRadius: borderRadius),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 26, color: fg),
            const SizedBox(width: 10),
            Flexible(
              child: Text(
                label,
                maxLines: 2,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 14,
                  height: 1.15,
                  fontWeight: on ? FontWeight.w700 : FontWeight.w500,
                  color: fg,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
