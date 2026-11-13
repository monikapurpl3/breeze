import 'package:flutter/material.dart';

import '../models.dart';
import '../theme.dart';
import '../haptics.dart';

/// Each mode's icon: the mode selector's, and the units list's.
const kModeIcons = <String, IconData>{
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
    this.rows = 1,
    this.fill = false,
  });

  final String value;
  final ValueChanged<String> onChanged;
  final bool enabled;

  /// One row of five, or two (three, then two) where the selector has a
  /// narrow column to itself: each mode then gets a bigger tile.
  final int rows;

  /// Tiles as tall as the selector is made, with bigger icons and labels: a
  /// tablet's, which has the height to spare.
  final bool fill;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    // A named group, so TalkBack says "Mode" on the way in, and each segment
    // says whether it is the selected one -- before this the colour was the
    // only sign, and a blind user could not find out which mode was on.
    return Semantics(
      container: true,
      label: 'Mode',
      child: Container(
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHighest.withValues(alpha: 0.4),
          borderRadius: BorderRadius.circular(20),
        ),
        padding: const EdgeInsets.all(4),
        child: rows < 2
            ? _row(kModes, scheme)
            : Column(
                mainAxisSize: fill ? MainAxisSize.max : MainAxisSize.min,
                children: [
                  _grow(_row(kModes.sublist(0, 3), scheme)),
                  const SizedBox(height: 4),
                  _grow(_row(kModes.sublist(3), scheme)),
                ],
              ),
      ),
    );
  }

  Widget _grow(Widget row) => fill ? Expanded(child: row) : row;

  Widget _row(List<String> modes, ColorScheme scheme) => Row(
        crossAxisAlignment: fill ? CrossAxisAlignment.stretch : CrossAxisAlignment.center,
        children: [
          for (final m in modes)
            Expanded(
              child: _Segment(
                selected: m == value,
                accent: accentForMode(m, scheme),
                icon: kModeIcons[m] ?? Icons.tune,
                label: kModeLabels[m] ?? m.toLowerCase(),
                fill: fill,
                onTap: enabled
                    ? () {
                        Haptics.select();
                        onChanged(m);
                      }
                    : null,
              ),
            ),
        ],
      );
}

class _Segment extends StatelessWidget {
  const _Segment({
    required this.selected,
    required this.accent,
    required this.icon,
    required this.label,
    this.fill = false,
    this.onTap,
  });

  final bool fill;
  final bool selected;
  final Color accent;
  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    // The label in a shade of the accent that can be read on the tinted fill
    // under it; the fill keeps the accent itself.
    final fg = selected
        ? readableAccent(
            accent,
            scheme,
            on: layeredOnSurface(scheme, [
              scheme.surfaceContainerHighest.withValues(alpha: 0.4),
              accent.withValues(alpha: 0.18),
            ]),
          )
        : scheme.onSurfaceVariant;
    return MergeSemantics(
      child: Semantics(
        button: true,
        selected: selected,
        inMutuallyExclusiveGroup: true,
        child: Material(
          color: selected ? accent.withValues(alpha: 0.18) : Colors.transparent,
          borderRadius: BorderRadius.circular(16),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: fill ? MainAxisSize.max : MainAxisSize.min,
                children: [
                  Icon(icon, size: fill ? 30 : 22, color: fg),
                  SizedBox(height: fill ? 6 : 3),
                  Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: fill ? 14 : 11,
                      fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                      color: fg,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
