import 'dart:async';

import 'package:flutter/material.dart';

import '../app_scope.dart';
import '../haptics.dart';
import '../models.dart';
import '../theme.dart';
import '../widgets/big_toggle.dart';
import '../widgets/fan_control.dart';
import '../widgets/flap_control.dart';
import '../widgets/mode_selector.dart';
import '../widgets/power_switch.dart';
import '../widgets/sleep_timer_sheet.dart';
import '../widgets/temp_control.dart';

/// One AC unit, filling the screen (no scrolling). Composed of the modern
/// control widgets; every change is a partial [ClimateSettings] delta handed
/// up via [onControl]. Rebuilds cheaply from an immutable [state]; the
/// interactive children hold their own drag state so a background refresh
/// never yanks a control the user is touching.
class UnitPage extends StatelessWidget {
  const UnitPage({
    super.key,
    required this.state,
    required this.onControl,
    this.refreshing = false,
    this.onRename,
    this.onRemove,
    this.sleepTimer,
    this.onSleepTimer,
  });

  final UnitState state;
  final ValueChanged<ClimateSettings> onControl;
  final bool refreshing;
  final VoidCallback? onRename;
  final VoidCallback? onRemove;

  /// The unit's pending one-shot timer, if the server has one for it.
  final SleepTimer? sleepTimer;

  /// Minutes to run for, or 0 to cancel. Null when the server is too old to
  /// support timers — the hourglass is then not shown at all, rather than
  /// offered and then failing.
  final ValueChanged<int>? onSleepTimer;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final accent = accentForMode(state.operationalMode, scheme);
    final unit = AppScope.of(context).tempUnit;
    final online = state.online;
    // Controls are live when the unit is reachable. (You can still retarget a
    // powered-off unit; only an unreachable one locks everything out.)
    final live = online;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
      child: Column(
        children: [
          // ---- header: status · refresh · name · hourglass · power · menu ----
          //
          // The refresh indicator used to sit immediately left of the power
          // switch, which is where the sleep-timer hourglass belongs — it is
          // about the switch. So the indicator moved next to the status dot,
          // where both "what is this unit doing" signals now live together, and
          // it no longer takes width from the name only while a command is in
          // flight (the row used to reflow as it appeared and vanished). The
          // name keeps the Expanded, so a long one ellipsises instead of
          // pushing anything off the edge.
          Row(
            children: [
              Icon(Icons.circle, size: 10, color: online ? accent : scheme.error),
              // Fixed-width slot: reserved whether or not the spinner is
              // visible, so the title never shifts sideways mid-command.
              SizedBox(
                width: 24,
                height: 16,
                child: Center(
                  child: AnimatedOpacity(
                    duration: const Duration(milliseconds: 150),
                    opacity: refreshing ? 1 : 0,
                    child: SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2, color: accent),
                    ),
                  ),
                ),
              ),
              Expanded(
                child: Text(
                  state.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                ),
              ),
              if (onSleepTimer != null)
                _SleepTimerButton(
                  timer: sleepTimer,
                  accent: accent,
                  enabled: live,
                  unitName: state.name,
                  onChosen: onSleepTimer!,
                ),
              PowerSwitch(
                on: state.powerState,
                enabled: live,
                onChanged: (v) => onControl(ClimateSettings(powerState: v)),
              ),
              if (onRename != null || onRemove != null)
                PopupMenuButton<String>(
                  onSelected: (v) {
                    if (v == 'rename') onRename?.call();
                    if (v == 'remove') onRemove?.call();
                  },
                  itemBuilder: (_) => [
                    if (onRename != null)
                      const PopupMenuItem(value: 'rename', child: Text('Rename')),
                    if (onRemove != null)
                      const PopupMenuItem(value: 'remove', child: Text('Remove')),
                  ],
                ),
            ],
          ),
          if (!online)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text('offline — last known settings',
                  style: TextStyle(color: scheme.error, fontSize: 13)),
            ),

          // ---- temperature hero (absorbs slack so the page fills) ----
          Expanded(
            child: TempControl(
              value: state.targetTemperature,
              indoor: state.indoorTemperature,
              outdoor: state.outdoorTemperature,
              accent: accent,
              unit: unit,
              enabled: live,
              onChanged: (t) => onControl(ClimateSettings(targetTemperature: t)),
            ),
          ),

          // ---- mode ----
          ModeSelector(
            value: state.operationalMode,
            enabled: live,
            onChanged: (m) => onControl(ClimateSettings(operationalMode: m)),
          ),
          const SizedBox(height: 12),

          // ---- fan ----
          FanControl(
            value: state.fanSpeed,
            accent: accent,
            enabled: live,
            onChanged: (f) => onControl(ClimateSettings(fanSpeed: f)),
          ),
          const SizedBox(height: 4),

          // ---- flap ----
          FlapControl(
            value: state.swingMode,
            accent: accent,
            enabled: live,
            onChanged: (s) => onControl(ClimateSettings(swingMode: s)),
          ),
          const SizedBox(height: 12),

          // ---- eco / turbo ----
          Row(
            children: [
              Expanded(
                child: BigToggle(
                  label: 'Eco',
                  icon: Icons.eco,
                  value: state.eco,
                  accent: const Color(0xFF4CAF50),
                  enabled: live,
                  onChanged: (v) => onControl(ClimateSettings(eco: v)),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: BigToggle(
                  label: 'Turbo',
                  icon: Icons.bolt,
                  value: state.turbo,
                  accent: const Color(0xFFFF7043),
                  enabled: live,
                  onChanged: (v) => onControl(ClimateSettings(turbo: v)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}


/// The hourglass beside the power switch: idle when nothing is pending, and a
/// live countdown when the server is holding a timer for this unit.
///
/// Stateful only to keep the countdown honest — [SleepTimer.remaining] is
/// derived from the server's `seconds_remaining` and the local elapsed time, so
/// it needs a periodic rebuild to tick down. One timer per visible unit page,
/// cancelled on dispose, and only while a countdown is actually running.
class _SleepTimerButton extends StatefulWidget {
  const _SleepTimerButton({
    required this.timer,
    required this.accent,
    required this.enabled,
    required this.unitName,
    required this.onChosen,
  });

  final SleepTimer? timer;
  final Color accent;
  final bool enabled;
  final String unitName;
  final ValueChanged<int> onChosen;

  @override
  State<_SleepTimerButton> createState() => _SleepTimerButtonState();
}

class _SleepTimerButtonState extends State<_SleepTimerButton> {
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    _syncTicker();
  }

  @override
  void didUpdateWidget(_SleepTimerButton old) {
    super.didUpdateWidget(old);
    _syncTicker();
  }

  void _syncTicker() {
    final running = widget.timer != null && !widget.timer!.expired;
    if (running && _ticker == null) {
      // Ten seconds, not one: the label is "42m", so a per-second rebuild would
      // burn battery to change nothing.
      _ticker = Timer.periodic(const Duration(seconds: 10), (_) {
        if (mounted) setState(() {});
      });
    } else if (!running) {
      _ticker?.cancel();
      _ticker = null;
    }
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  Future<void> _open() async {
    Haptics.tick();
    final chosen = await SleepTimerSheet.show(
      context,
      unitName: widget.unitName,
      existing: widget.timer,
    );
    if (chosen != null) widget.onChosen(chosen);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final t = widget.timer;
    final active = t != null && !t.expired;
    final colour = !widget.enabled
        ? scheme.onSurfaceVariant.withValues(alpha: 0.4)
        : (active ? widget.accent : scheme.onSurfaceVariant);

    return Tooltip(
      message: active
          ? 'Turns off at ${t.firesAtClock}'
          : 'Turn off after a while',
      child: InkWell(
        onTap: widget.enabled ? _open : null,
        borderRadius: BorderRadius.circular(20),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
          child: Row(
            children: [
              Icon(
                active ? Icons.hourglass_bottom : Icons.hourglass_empty,
                size: 20,
                color: colour,
              ),
              // The remaining time only appears when there is one, so an idle
              // header stays as narrow as it was before this feature existed.
              if (active) ...[
                const SizedBox(width: 3),
                Text(
                  t.shortLabel,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: colour,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
