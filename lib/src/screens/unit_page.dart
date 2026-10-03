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
import '../widgets/timer_sheet.dart';
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
    this.startTimer,
    this.startsSupported = false,
    this.onTimer,
  });

  final UnitState state;
  final ValueChanged<ClimateSettings> onControl;
  final bool refreshing;
  final VoidCallback? onRename;
  final VoidCallback? onRemove;

  /// The unit's pending sleep timer, if the server has one for it.
  final UnitTimer? sleepTimer;

  /// The unit's pending scheduled start (Breeze Core 4.2.0), if any.
  final UnitTimer? startTimer;

  /// Whether the server takes scheduled starts (`timer_at`); without it the
  /// timer sheet offers only the sleep timer.
  final bool startsSupported;

  /// What the timer sheet chose. Null when the server is too old to support
  /// timers — the button is then not shown at all, rather than offered and
  /// then failing.
  final ValueChanged<TimerChoice>? onTimer;

  @override
  Widget build(BuildContext context) {
    // With large text (Android's font size from "Large", 1.15x, up) the
    // page no longer fits a small phone, and the bottom controls were cut off
    // with no way to reach them. Then it scrolls: at least the screen tall,
    // so the temperature still takes the slack when there is some.
    final largeText = MediaQuery.textScalerOf(context).scale(10) > 11;
    if (!largeText) return _page(context);
    return LayoutBuilder(
      builder: (context, box) => SingleChildScrollView(
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: box.maxHeight),
          child: IntrinsicHeight(child: _page(context)),
        ),
      ),
    );
  }

  Widget _page(BuildContext context) {
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
                // A heading, so a screen reader can jump unit to unit.
                child: Semantics(
                  header: true,
                  child: Text(
                    state.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                  ),
                ),
              ),
              if (onTimer != null)
                _TimerButton(
                  sleep: sleepTimer,
                  start: startTimer,
                  startsSupported: startsSupported,
                  accent: accent,
                  enabled: live,
                  unitName: state.name,
                  onChosen: onTimer!,
                ),
              PowerSwitch(
                on: state.powerState,
                enabled: live,
                onChanged: (v) => onControl(ClimateSettings(powerState: v)),
              ),
              if (onRename != null || onRemove != null)
                PopupMenuButton<String>(
                  tooltip: 'More options for ${state.name}',
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
              // Said when the unit drops off, not only shown in red.
              child: Semantics(
                liveRegion: true,
                child: Text('offline — last known settings',
                    style: TextStyle(color: scheme.error, fontSize: 13)),
              ),
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


/// The timer button beside the power switch: idle when nothing is pending; an
/// hourglass and a countdown while a sleep timer runs; an alarm clock and when
/// while a scheduled start waits.
///
/// Stateful only to keep the countdown honest — [UnitTimer.remaining] is
/// derived from the server's `seconds_remaining` and the local elapsed time, so
/// it needs a periodic rebuild to tick down. One timer per visible unit page,
/// cancelled on dispose, and only while something is actually pending.
class _TimerButton extends StatefulWidget {
  const _TimerButton({
    required this.sleep,
    required this.start,
    required this.startsSupported,
    required this.accent,
    required this.enabled,
    required this.unitName,
    required this.onChosen,
  });

  final UnitTimer? sleep;
  final UnitTimer? start;
  final bool startsSupported;
  final Color accent;
  final bool enabled;
  final String unitName;
  final ValueChanged<TimerChoice> onChosen;

  @override
  State<_TimerButton> createState() => _TimerButtonState();
}

class _TimerButtonState extends State<_TimerButton> {
  Timer? _ticker;

  bool get _sleeping => widget.sleep != null && !widget.sleep!.expired;
  bool get _starting => widget.start != null && !widget.start!.expired;

  @override
  void initState() {
    super.initState();
    _syncTicker();
  }

  @override
  void didUpdateWidget(_TimerButton old) {
    super.didUpdateWidget(old);
    _syncTicker();
  }

  void _syncTicker() {
    final running = _sleeping || _starting;
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
    final chosen = await TimerSheet.show(
      context,
      unitName: widget.unitName,
      sleep: widget.sleep,
      start: widget.start,
      startsSupported: widget.startsSupported,
    );
    if (chosen != null) widget.onChosen(chosen);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final sleep = widget.sleep;
    final start = widget.start;
    final sleeping = _sleeping;
    final starting = _starting;
    Color colour(bool active) => !widget.enabled
        ? scheme.onSurfaceVariant.withValues(alpha: 0.4)
        : (active ? widget.accent : scheme.onSurfaceVariant);
    final label = Theme.of(context).textTheme.labelSmall;

    final tips = [
      if (sleeping) 'Turns off at ${sleep!.firesAtClock}',
      if (starting) 'Turns on ${start!.whenLabel}',
    ];

    final idle = widget.startsSupported ? 'Turn off or on later' : 'Turn off after a while';
    final button = Tooltip(
      message: tips.isEmpty ? idle : tips.join('\n'),
      child: InkWell(
        onTap: widget.enabled ? _open : null,
        borderRadius: BorderRadius.circular(20),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Idle: the hourglass it always was, so a header with nothing
              // pending stays exactly as narrow as before starts existed.
              if (sleeping || !starting)
                Icon(
                  sleeping ? Icons.hourglass_bottom : Icons.hourglass_empty,
                  size: 20,
                  color: colour(sleeping),
                ),
              if (sleeping) ...[
                const SizedBox(width: 3),
                Text(
                  sleep!.shortLabel,
                  style: label?.copyWith(color: colour(true), fontWeight: FontWeight.w600),
                ),
              ],
              if (starting) ...[
                if (sleeping) const SizedBox(width: 6),
                Icon(Icons.alarm_on, size: 20, color: colour(true)),
                // Both at once would crowd the unit's name; the countdown is
                // the one that is soon, and the tooltip and sheet say the rest.
                if (!sleeping) ...[
                  const SizedBox(width: 3),
                  Text(
                    start!.shortWhen,
                    style: label?.copyWith(color: colour(true), fontWeight: FontWeight.w600),
                  ),
                ],
              ],
            ],
          ),
        ),
      ),
    );

    // One named button, "Timer, turns off at 23:30" -- it was an unnamed tap
    // target whose state was a glyph and "42m" -- and at least 48dp square.
    return Semantics(
      button: true,
      enabled: widget.enabled,
      label: tips.isEmpty ? 'Timer, ${idle.toLowerCase()}' : 'Timer',
      value: tips.join(', '),
      onTap: widget.enabled ? _open : null,
      excludeSemantics: true,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
        child: button,
      ),
    );
  }
}
