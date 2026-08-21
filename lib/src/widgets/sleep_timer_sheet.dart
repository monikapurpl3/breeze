import 'package:flutter/material.dart';

import '../models.dart';
import '../haptics.dart';

/// The sheet behind the hourglass: pick how long the unit should stay on, or
/// look at / cancel the timer that is already running.
///
/// Returns:
///   * a positive int — set a timer for that many minutes
///   * 0             — cancel the existing timer
///   * null          — dismissed, change nothing
class SleepTimerSheet extends StatelessWidget {
  const SleepTimerSheet({super.key, required this.unitName, this.existing});

  final String unitName;
  final SleepTimer? existing;

  /// The presets people actually reach for. "Until I fall asleep" is 30–60;
  /// two hours is the outer edge of an evening. Anything else is what the
  /// custom row is for.
  static const List<int> presets = [15, 30, 45, 60, 90, 120];

  static Future<int?> show(
    BuildContext context, {
    required String unitName,
    SleepTimer? existing,
  }) => showModalBottomSheet<int>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (_) => SleepTimerSheet(unitName: unitName, existing: existing),
  );

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final active = existing != null && !existing!.expired;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(Icons.hourglass_bottom, color: scheme.primary),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    active ? 'Turning off in ${existing!.shortLabel}' : 'Turn off later',
                    style: text.titleMedium?.copyWith(fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              active
                  ? '$unitName switches off at ${existing!.firesAtClock}. '
                        'The server does it, so this works with the phone off.'
                  : 'Leave $unitName running for a while, then let the server '
                        'switch it off — no need for the phone to be here.',
              style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: 18),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final m in presets)
                  ActionChip(
                    label: Text(_label(m)),
                    onPressed: () {
                      Haptics.select();
                      Navigator.pop(context, m);
                    },
                  ),
                ActionChip(
                  avatar: const Icon(Icons.edit, size: 16),
                  label: const Text('Custom'),
                  onPressed: () async {
                    final chosen = await _askCustom(context);
                    if (chosen != null && context.mounted) {
                      Navigator.pop(context, chosen);
                    }
                  },
                ),
              ],
            ),
            if (active) ...[
              const SizedBox(height: 16),
              TextButton.icon(
                onPressed: () {
                  Haptics.toggle();
                  Navigator.pop(context, 0);
                },
                icon: const Icon(Icons.cancel_outlined),
                label: const Text('Cancel the timer'),
                style: TextButton.styleFrom(foregroundColor: scheme.error),
              ),
            ],
          ],
        ),
      ),
    );
  }

  static String _label(int minutes) =>
      minutes < 60 ? '$minutes min' : (minutes % 60 == 0
          ? '${minutes ~/ 60} h'
          : '${minutes ~/ 60} h ${minutes % 60}');

  Future<int?> _askCustom(BuildContext context) async {
    final controller = TextEditingController();
    return showDialog<int>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Turn off after'),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            suffixText: 'minutes',
            // The server's own ceiling. Saying it here beats a 422 later.
            helperText: '1 to 1440 (24 h)',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              final v = int.tryParse(controller.text.trim());
              if (v == null || v < 1 || v > 1440) return;
              Navigator.pop(ctx, v);
            },
            child: const Text('Set'),
          ),
        ],
      ),
    );
  }
}
