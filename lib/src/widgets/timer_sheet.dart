import 'package:flutter/material.dart';

import '../models.dart';
import '../haptics.dart';

/// What the timer sheet was asked to do. Null from [TimerSheet.show] means it
/// was dismissed and nothing changes.
sealed class TimerChoice {
  const TimerChoice();
}

/// Switch off after [minutes].
class SleepFor extends TimerChoice {
  const SleepFor(this.minutes);
  final int minutes;
}

/// Switch on [days] from the server's today (0 = today) at [at], an `HH:MM` on
/// the server's clock.
class StartAt extends TimerChoice {
  const StartAt(this.days, this.at);
  final int days;
  final String at;
}

/// Cancel [timer], whichever kind it is.
class CancelTimer extends TimerChoice {
  const CancelTimer(this.timer);
  final UnitTimer timer;
}

/// The sheet behind the timer button: turn the unit off after a while, or
/// (Breeze Core 4.2.0) on at a set time — and look at or cancel either one
/// that is already pending. A unit has at most one of each.
class TimerSheet extends StatefulWidget {
  const TimerSheet({
    super.key,
    required this.unitName,
    this.sleep,
    this.start,
    this.startsSupported = false,
  });

  final String unitName;
  final UnitTimer? sleep;
  final UnitTimer? start;

  /// False on a server without `timer_at`: the "turn on later" half is then
  /// not shown at all, rather than offered and then failing.
  final bool startsSupported;

  /// The presets people actually reach for. "Until I fall asleep" is 30–60;
  /// two hours is the outer edge of an evening. Anything else is what the
  /// custom row is for.
  static const List<int> presets = [15, 30, 45, 60, 90, 120];

  /// The server's ceiling for a scheduled start.
  static const int maxStartDays = 30;

  static Future<TimerChoice?> show(
    BuildContext context, {
    required String unitName,
    UnitTimer? sleep,
    UnitTimer? start,
    bool startsSupported = false,
  }) => showModalBottomSheet<TimerChoice>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (_) => TimerSheet(
      unitName: unitName,
      sleep: sleep,
      start: start,
      startsSupported: startsSupported,
    ),
  );

  /// "Today", "Tomorrow", "In 5 days".
  static String dayLabel(int days) => switch (days) {
    0 => 'Today',
    1 => 'Tomorrow',
    _ => 'In $days days',
  };

  static String hhmm(TimeOfDay t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  @override
  State<TimerSheet> createState() => _TimerSheetState();
}

class _TimerSheetState extends State<TimerSheet> {
  // Opens on the pending start, if there is one, so changing only its time
  // does not quietly move its day. Otherwise tomorrow at seven.
  int _days = 1;
  TimeOfDay _time = const TimeOfDay(hour: 7, minute: 0);

  @override
  void initState() {
    super.initState();
    final s = widget.start;
    if (s != null && !s.expired) {
      final d = s.daysAhead;
      if (d != null && d >= 0 && d <= TimerSheet.maxStartDays) _days = d;
      final clock = s.firesAtClock.split(':');
      final h = clock.isNotEmpty ? int.tryParse(clock[0]) : null;
      final m = clock.length > 1 ? int.tryParse(clock[1]) : null;
      if (h != null && m != null) _time = TimeOfDay(hour: h, minute: m);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _offSection(context),
            if (widget.startsSupported) ...[
              const SizedBox(height: 12),
              const Divider(),
              const SizedBox(height: 12),
              _onSection(context),
            ],
          ],
        ),
      ),
    );
  }

  Widget _heading(BuildContext context, IconData icon, String title) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      children: [
        Icon(icon, color: scheme.primary),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            title,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
          ),
        ),
      ],
    );
  }

  Widget _blurb(BuildContext context, String text) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Text(
        text,
        style: Theme.of(context).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
      ),
    );
  }

  Widget _cancel(BuildContext context, UnitTimer timer, String label) {
    final scheme = Theme.of(context).colorScheme;
    return Align(
      alignment: Alignment.centerLeft,
      child: TextButton.icon(
        onPressed: () {
          Haptics.toggle();
          Navigator.pop(context, CancelTimer(timer));
        },
        icon: const Icon(Icons.cancel_outlined),
        label: Text(label),
        style: TextButton.styleFrom(foregroundColor: scheme.error),
      ),
    );
  }

  // --- switch off -----------------------------------------------------------

  Widget _offSection(BuildContext context) {
    final sleep = widget.sleep;
    final active = sleep != null && !sleep.expired;
    final name = widget.unitName;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _heading(
          context,
          Icons.hourglass_bottom,
          active ? 'Turning off in ${sleep.shortLabel}' : 'Turn off later',
        ),
        _blurb(
          context,
          active
              ? '$name switches off at ${sleep.firesAtClock}. '
                    'The server does it, so this works with the phone off.'
              : 'Leave $name running for a while, then let the server '
                    'switch it off — no need for the phone to be here.',
        ),
        const SizedBox(height: 18),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final m in TimerSheet.presets)
              ActionChip(
                label: Text(_label(m)),
                onPressed: () {
                  Haptics.select();
                  Navigator.pop(context, SleepFor(m));
                },
              ),
            ActionChip(
              avatar: const Icon(Icons.edit, size: 16),
              label: const Text('Custom'),
              onPressed: () async {
                final chosen = await _askCustom(context);
                if (chosen != null && context.mounted) {
                  Navigator.pop(context, SleepFor(chosen));
                }
              },
            ),
          ],
        ),
        if (active) ...[
          const SizedBox(height: 8),
          _cancel(context, sleep, 'Cancel the timer'),
        ],
      ],
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

  // --- switch on later ------------------------------------------------------

  Widget _onSection(BuildContext context) {
    final start = widget.start;
    final pending = start != null && !start.expired;
    final name = widget.unitName;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _heading(
          context,
          Icons.alarm,
          pending ? 'Turning on ${start.whenLabel}' : 'Turn on later',
        ),
        _blurb(
          context,
          pending
              ? '$name switches on with the mode and temperature it last had. '
                    'Pick another day or time to move it.'
              : 'Switch $name on at a set time, up to ${TimerSheet.maxStartDays} '
                    'days ahead, with the mode and temperature it last had. The '
                    'time is the server\'s clock, the same one schedules use.',
        ),
        const SizedBox(height: 14),
        Row(
          children: [
            Expanded(
              child: DropdownButtonFormField<int>(
                initialValue: _days,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'Day',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                items: [
                  for (var d = 0; d <= TimerSheet.maxStartDays; d++)
                    DropdownMenuItem(value: d, child: Text(TimerSheet.dayLabel(d))),
                ],
                onChanged: (d) => setState(() => _days = d ?? _days),
              ),
            ),
            const SizedBox(width: 12),
            OutlinedButton.icon(
              onPressed: () async {
                Haptics.tick();
                final picked = await showTimePicker(
                  context: context,
                  initialTime: _time,
                  helpText: 'Turn on at (server time)',
                );
                if (picked != null && mounted) setState(() => _time = picked);
              },
              icon: const Icon(Icons.schedule, size: 18),
              label: Text(TimerSheet.hhmm(_time)),
            ),
          ],
        ),
        const SizedBox(height: 12),
        FilledButton.icon(
          onPressed: () {
            Haptics.select();
            Navigator.pop(context, StartAt(_days, TimerSheet.hhmm(_time)));
          },
          icon: const Icon(Icons.alarm_on),
          label: Text(pending ? 'Move it' : 'Turn on then'),
        ),
        if (pending) ...[
          const SizedBox(height: 4),
          _cancel(context, start, 'Cancel the start'),
        ],
      ],
    );
  }
}
