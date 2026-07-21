import 'package:flutter/material.dart';

import '../models.dart';
import '../theme.dart';

const _modeIcons = <String, IconData>{
  'AUTO': Icons.auto_mode,
  'COOL': Icons.ac_unit,
  'DRY': Icons.water_drop_outlined,
  'HEAT': Icons.local_fire_department,
  'FAN_ONLY': Icons.air,
};

/// A modern segmented mode picker. The selected segment fills with that
/// mode's own accent hue (cool/heat/dry/…), so the control is colourful and
/// the current mode reads at a glance.
class ModeSelector extends StatelessWidget {
  const ModeSelector({
    super.key,
    required this.value,
    required this.onChanged,
    this.enabled = true,
  });

  final String value;
  final ValueChanged<String> onChanged;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(20),
      ),
      padding: const EdgeInsets.all(4),
      child: Row(
        children: [
          for (final m in kModes)
            Expanded(
              child: _Segment(
                selected: m == value,
                accent: accentForMode(m, scheme),
                icon: _modeIcons[m] ?? Icons.tune,
                label: kModeLabels[m] ?? m.toLowerCase(),
                onTap: enabled ? () => onChanged(m) : null,
              ),
            ),
        ],
      ),
    );
  }
}

class _Segment extends StatelessWidget {
  const _Segment({
    required this.selected,
    required this.accent,
    required this.icon,
    required this.label,
    this.onTap,
  });

  final bool selected;
  final Color accent;
  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final fg = selected ? accent : scheme.onSurfaceVariant;
    return Material(
      color: selected ? accent.withValues(alpha: 0.18) : Colors.transparent,
      borderRadius: BorderRadius.circular(16),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 22, color: fg),
              const SizedBox(height: 3),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                  color: fg,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
