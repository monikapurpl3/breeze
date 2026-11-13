import 'dart:async';

import 'package:flutter/material.dart';

import '../app_scope.dart';
import '../haptics.dart';
import '../models.dart';
import '../theme.dart';
import '../layout.dart';
import '../widgets/big_toggle.dart';
import '../widgets/fan_control.dart';
import '../widgets/fit_to_space.dart';
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
    return LayoutBuilder(builder: (context, box) {
      final size = box.biggest;
      if (largeText) {
        // Sideways, the controls column scrolls on its own beside the
        // temperature; upright, the whole page does, as it always has.
        if (pageIsLandscape(size)) return _landscape(context);
        return SingleChildScrollView(
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: box.maxHeight),
            child: IntrinsicHeight(child: _portrait(context)),
          ),
        );
      }
      if (box.hasBoundedWidth && box.hasBoundedHeight && pageIsRoomy(size)) {
        return SizedBox.fromSize(size: size, child: _roomy(context, size));
      }
      return pageIsLandscape(size) ? _landscape(context) : _portrait(context);
    });
  }

  /// A tablet, an open foldable: every part bigger, all of them together.
  /// The header keeps its size, so a long name still fits beside the
  /// switch; below it, the parts are laid out to the space's proportions and
  /// drawn to fill it. Whatever height is left over goes, on a tablet, into
  /// the parts themselves -- taller tiles, thicker sliders, a bigger readout
  /// -- each by its share; on an open foldable, between them, which are never
  /// closer than [gap] even when nothing is left over.
  Widget _roomy(BuildContext context, Size size) {
    final p = _Parts.of(context, this);
    final landscape = size.width > size.height * 1.1;
    final thick = isTabletWindow(context);
    const gap = 14.0;
    Widget column(List<(int, Widget)> parts) {
      final children = <Widget>[];
      for (final (share, part) in parts) {
        if (!thick) {
          children.add(Padding(padding: const EdgeInsets.symmetric(vertical: gap / 2), child: part));
          continue;
        }
        if (children.isNotEmpty) children.add(const SizedBox(height: gap));
        children.add(Expanded(flex: share, child: part));
      }
      return Column(
        mainAxisAlignment: thick ? MainAxisAlignment.start : MainAxisAlignment.spaceEvenly,
        children: children,
      );
    }

    final hero = _hero(context, p, fill: thick);
    final ecoTurbo = _ecoTurbo(p, fill: thick);
    final fan = _fan(p, fill: thick);
    final flap = _flap(p, fill: thick);
    // Measured at the height its parts want before it is given more.
    final body = IntrinsicHeight(
      child: landscape
          // Modes on two rows: the column is narrow, and a bigger tile per
          // mode beats five small ones.
          ? Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(child: column([(5, hero), (3, ecoTurbo)])),
                const SizedBox(width: 28),
                Expanded(
                  child: column([(4, _mode(p, rows: 2, fill: thick)), (3, fan), (2, flap)]),
                ),
              ],
            )
          : column([(5, hero), (2, _mode(p, fill: thick)), (3, fan), (2, flap), (3, ecoTurbo)]),
    );
    return Padding(
      // Thick parts reach their edges; a little more room under them.
      padding: EdgeInsets.fromLTRB(20, 8, 20, thick ? 18 : 8),
      child: Column(
        children: [
          _header(context, p),
          if (!p.online) _offline(context, p),
          Expanded(
            child: FitToSpace(
              // Never so narrow that a flap's label wraps.
              minWidth: landscape ? 640 : 360,
              maxWidth: landscape ? 1100 : 600,
              child: body,
            ),
          ),
        ],
      ),
    );
  }

  /// One column, top to bottom: what a phone held upright shows.
  Widget _portrait(BuildContext context) {
    final p = _Parts.of(context, this);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
      child: Column(
        children: [
          _header(context, p),
          if (!p.online) _offline(context, p),
          // ---- temperature hero (absorbs slack so the page fills) ----
          Expanded(child: _hero(context, p)),
          ..._controls(context, p),
          const SizedBox(height: 12),
          _ecoTurbo(p),
        ],
      ),
    );
  }

  /// Sideways: the temperature on the left, the controls beside it. On a
  /// phone the controls column scrolls if it is taller than the screen is.
  Widget _landscape(BuildContext context) {
    final p = _Parts.of(context, this);
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 8),
      child: Column(
        children: [
          _header(context, p),
          if (!p.online) _offline(context, p),
          Expanded(
            child: Row(
              children: [
                // Fills the height where there is room; on a phone on its
                // side, a few pixels short, it scrolls rather than clips.
                Expanded(
                  child: LayoutBuilder(
                    builder: (context, box) => SingleChildScrollView(
                      child: ConstrainedBox(
                        constraints: BoxConstraints(minHeight: box.maxHeight),
                        child: IntrinsicHeight(
                          child: Column(
                            children: [
                              Expanded(child: _hero(context, p)),
                              _ecoTurbo(p),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 32),
                Expanded(
                  child: LayoutBuilder(
                    builder: (context, box) => SingleChildScrollView(
                      child: ConstrainedBox(
                        constraints: BoxConstraints(minHeight: box.maxHeight),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const SizedBox(height: 8),
                            ..._controls(context, p),
                            const SizedBox(height: 8),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _header(BuildContext context, _Parts p) {
    final scheme = p.scheme;
    final accent = p.accent;
    final online = p.online;
    final live = p.live;
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
    return Row(
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
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Semantics(
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
              // Switched on from the Nerd screen's Internal tab.
              if (AppScope.of(context).internal.showUnitIp && state.ip.isNotEmpty)
                SelectableText(
                  state.ip,
                  maxLines: 1,
                  style: TextStyle(
                    fontSize: 12,
                    color: scheme.onSurfaceVariant,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
            ],
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
    );
  }

  Widget _offline(BuildContext context, _Parts p) {
    final scheme = p.scheme;
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      // Said when the unit drops off, not only shown in red.
      child: Semantics(
        liveRegion: true,
        child: Text('offline — last known settings',
            style: TextStyle(color: scheme.error, fontSize: 13)),
      ),
    );
  }

  Widget _hero(BuildContext context, _Parts p, {bool fill = false}) => TempControl(
        value: state.targetTemperature,
        indoor: state.indoorTemperature,
        outdoor: state.outdoorTemperature,
        accent: p.accent,
        unit: p.unit,
        enabled: p.live,
        fill: fill,
        onChanged: (t) => onControl(ClimateSettings(targetTemperature: t)),
      );

  /// Mode, fan and flaps, spaced as a phone shows them.
  List<Widget> _controls(BuildContext context, _Parts p, {int modeRows = 1}) => [
        _mode(p, rows: modeRows),
        const SizedBox(height: 12),
        _fan(p),
        const SizedBox(height: 4),
        _flap(p),
      ];

  Widget _mode(_Parts p, {int rows = 1, bool fill = false}) => ModeSelector(
        value: state.operationalMode,
        rows: rows,
        fill: fill,
        enabled: p.live,
        onChanged: (m) => onControl(ClimateSettings(operationalMode: m)),
      );

  Widget _fan(_Parts p, {bool fill = false}) => FanControl(
        value: state.fanSpeed,
        accent: p.accent,
        enabled: p.live,
        fill: fill,
        onChanged: (f) => onControl(ClimateSettings(fanSpeed: f)),
      );

  Widget _flap(_Parts p, {bool fill = false}) => FlapControl(
        value: state.swingMode,
        accent: p.accent,
        enabled: p.live,
        fill: fill,
        onChanged: (s) => onControl(ClimateSettings(swingMode: s)),
      );

  /// Eco and turbo, side by side.
  Widget _ecoTurbo(_Parts p, {bool fill = false}) {
    final live = p.live;
    return Row(
      crossAxisAlignment: fill ? CrossAxisAlignment.stretch : CrossAxisAlignment.center,
      children: [
        Expanded(
          child: BigToggle(
            label: 'Eco',
            icon: Icons.eco,
            value: state.eco,
            accent: const Color(0xFF4CAF50),
            enabled: live,
            fill: fill,
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
            fill: fill,
            onChanged: (v) => onControl(ClimateSettings(turbo: v)),
          ),
        ),
      ],
    );
  }
}

/// What every part of the page reads, worked out once per build.
class _Parts {
  _Parts._(this.scheme, this.accent, this.unit, this.online);

  factory _Parts.of(BuildContext context, UnitPage page) {
    final scheme = Theme.of(context).colorScheme;
    return _Parts._(
      scheme,
      accentForMode(page.state.operationalMode, scheme),
      AppScope.of(context).tempUnit,
      page.state.online,
    );
  }

  final ColorScheme scheme;
  final Color accent;
  final String unit;
  final bool online;

  // Controls are live when the unit is reachable. (You can still retarget a
  // powered-off unit; only an unreachable one locks everything out.)
  bool get live => online;
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
