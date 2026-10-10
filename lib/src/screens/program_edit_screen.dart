import 'package:flutter/material.dart';

import '../api_client.dart';
import '../app_scope.dart';
import '../haptics.dart';
import '../models.dart';
import '../theme.dart';
import '../util.dart';
import '../widgets/curve_painter.dart';
import '../widgets/fan_control.dart';
import '../widgets/mode_selector.dart';
import '../widgets/scene_editor.dart';

/// Create or edit a program: a favourite (a scene applied on demand), a
/// schedule (scenes at times of the week) or a curve (a setpoint that follows
/// the day). Scenes are edited with the control screen's own controls.
class ProgramEditScreen extends StatefulWidget {
  final List<UnitSummary> units;
  final Program? existing;
  const ProgramEditScreen({super.key, required this.units, this.existing});
  @override
  State<ProgramEditScreen> createState() => _ProgramEditScreenState();
}

const _kinds = ['favourite', 'schedule', 'curve'];

IconData kindIcon(String kind) => switch (kind) {
      'schedule' => Icons.calendar_month,
      'curve' => Icons.show_chart,
      _ => Icons.star_rounded,
    };

String kindName(String kind) => switch (kind) {
      'schedule' => 'Schedule',
      'curve' => 'Curve',
      _ => 'Favourite',
    };

String _kindBlurb(String kind) => switch (kind) {
      'schedule' => 'Scenes at set times on the days you pick. The server runs '
          'them, so they happen with the phone off. Times are the server\'s.',
      'curve' => 'A target temperature that follows the day, adjusted by the '
          'server as the hours pass, through midnight and round again.',
      _ => 'A scene saved for one tap: apply it from Programs whenever you want it.',
    };

const _weekdays = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];

/// "Every day", "Weekdays", "Weekends", or the days themselves.
String daysLabel(List<int> days) {
  final d = {...days};
  if (d.isEmpty || d.length == 7) return 'Every day';
  if (d.length == 5 && d.containsAll([0, 1, 2, 3, 4])) return 'Weekdays';
  if (d.length == 2 && d.containsAll([5, 6])) return 'Weekends';
  return (d.toList()..sort()).map((i) => kWeekdayShort[i]).join(', ');
}

ClimateSettings _defaultScene() => ClimateSettings(
      powerState: true,
      operationalMode: 'COOL',
      targetTemperature: 22.0,
      fanSpeed: 102,
      swingMode: 'OFF',
      eco: false,
      turbo: false,
    );

class _ProgramEditScreenState extends State<ProgramEditScreen> {
  late final TextEditingController _name;
  bool _enabled = true;
  String _kind = 'favourite';
  final Set<String> _units = {};
  late ClimateSettings _favourite;
  late List<ScheduleEntry> _schedule;
  late CurveConfig _curve;
  bool _saving = false;

  ApiClient get _api => AppScope.of(context).api!;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _name = TextEditingController(text: e?.name ?? '');
    _enabled = e?.enabled ?? true;
    _kind = e?.kind ?? 'favourite';
    _units.addAll(e?.unitIds ?? const []);
    _favourite = SceneEditor.complete(e?.favourite ?? _defaultScene());
    _schedule = e?.schedule
            .map((s) => ScheduleEntry(days: [...s.days], time: s.time, settings: s.settings.copy()))
            .toList() ??
        [];
    _curve = e?.curve != null
        ? CurveConfig(
            operationalMode: e!.curve!.operationalMode,
            fanSpeed: e.curve!.fanSpeed,
            points: e.curve!.points.map((p) => CurvePoint(time: p.time, temperature: p.temperature)).toList())
        : CurveConfig(points: [
            CurvePoint(time: '08:00', temperature: 24.0),
            CurvePoint(time: '22:00', temperature: 20.0),
          ]);
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    if (name.isEmpty) {
      _snack('Give the program a name.');
      return;
    }
    if (_kind == 'schedule' && _schedule.isEmpty) {
      _snack('Add at least one time.');
      return;
    }
    if (_kind == 'curve' && _curve.points.length < 2) {
      _snack('A curve needs at least two points.');
      return;
    }
    final prog = Program(
      id: widget.existing?.id ?? '',
      name: name,
      enabled: _enabled,
      unitIds: _units.toList(),
      kind: _kind,
      favourite: _kind == 'favourite' ? _favourite : null,
      schedule: _kind == 'schedule' ? _schedule : [],
      curve: _kind == 'curve' ? _curve : null,
    );
    setState(() => _saving = true);
    try {
      if (widget.existing == null) {
        await _api.createProgram(prog);
      } else {
        await _api.updateProgram(prog);
      }
      Haptics.success();
      if (mounted) Navigator.pop(context, true);
    } on ApiException catch (e) {
      Haptics.failure();
      _snack(e.message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _snack(String m) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.existing == null ? 'New program' : 'Edit program'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: FilledButton.icon(
              onPressed: _saving ? null : _save,
              icon: _saving
                  ? const SizedBox(
                      width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.check),
              label: const Text('Save'),
            ),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 40),
        children: [
          TextField(
            controller: _name,
            textCapitalization: TextCapitalization.sentences,
            style: Theme.of(context).textTheme.titleLarge,
            decoration: InputDecoration(
              labelText: 'Name',
              hintText: switch (_kind) {
                'schedule' => 'Weekday mornings',
                'curve' => 'Summer nights',
                _ => 'Cosy evening',
              },
              filled: true,
              prefixIcon: Icon(kindIcon(_kind)),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide.none,
              ),
            ),
          ),
          const SizedBox(height: 16),
          _KindPicker(value: _kind, onChanged: (k) => setState(() => _kind = k)),
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 8, 4, 0),
            child: Text(_kindBlurb(_kind), style: _hint(context)),
          ),
          const SizedBox(height: 12),
          _Section(
            title: 'Units',
            child: _UnitPicker(
              units: widget.units,
              selected: _units,
              onChanged: () => setState(() {}),
            ),
          ),
          // On/off is the server's scheduler's business: it runs enabled
          // schedules and curves. A favourite applies the same either way, so
          // it gets no switch (and keeps whatever value it had).
          if (_kind != 'favourite')
            _Section(
              title: 'Running',
              child: SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(_enabled ? 'On' : 'Off'),
                subtitle: Text(_kind == 'schedule'
                    ? 'Off keeps the times, but nothing happens at them'
                    : 'Off keeps the curve, but the server stops following it'),
                value: _enabled,
                onChanged: (v) => setState(() => _enabled = v),
              ),
            ),
          if (_kind == 'favourite')
            _Section(
              title: 'Scene',
              child: SceneEditor(initial: _favourite, onChanged: (s) => _favourite = s),
            ),
          if (_kind == 'schedule') ..._scheduleSection(),
          if (_kind == 'curve') ..._curveSection(),
        ],
      ),
    );
  }

  // --- schedule --------------------------------------------------------------

  List<Widget> _scheduleSection() {
    final sorted = [..._schedule]..sort((a, b) => minutesOf(a.time).compareTo(minutesOf(b.time)));
    return [
      Padding(
        padding: const EdgeInsets.fromLTRB(4, 16, 4, 8),
        child: _Heading(
          'Times',
          trailing: '${_schedule.length} ${_schedule.length == 1 ? 'time' : 'times'}',
        ),
      ),
      if (sorted.isEmpty)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Text('No times yet.', textAlign: TextAlign.center, style: _hint(context)),
        ),
      for (final entry in sorted)
        _EntryCard(
          key: ObjectKey(entry),
          entry: entry,
          onPickTime: () => _pickTime(entry),
          onDays: (days) => setState(() => entry.days = days),
          onEditScene: () => _editScene(entry),
          onDelete: () => setState(() => _schedule.remove(entry)),
        ),
      const SizedBox(height: 8),
      FilledButton.tonalIcon(
        onPressed: _addEntry,
        icon: const Icon(Icons.add_alarm),
        label: const Text('Add a time'),
      ),
    ];
  }

  Future<void> _pickTime(ScheduleEntry entry) async {
    final t = await showTimePicker(context: context, initialTime: parseHHMM(entry.time));
    if (t != null) setState(() => entry.time = hhmm(t));
  }

  Future<void> _addEntry() async {
    final t = await showTimePicker(
      context: context,
      initialTime: const TimeOfDay(hour: 7, minute: 0),
      helpText: 'When should it happen?',
    );
    if (t == null) return;
    final last = _schedule.isEmpty ? null : _schedule.last;
    setState(() => _schedule.add(ScheduleEntry(
          days: last == null ? [0, 1, 2, 3, 4] : [...last.days],
          time: hhmm(t),
          settings: last?.settings.copy() ?? _defaultScene(),
        )));
  }

  Future<void> _editScene(ScheduleEntry entry) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (ctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.92,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        builder: (ctx, scroll) => ListView(
          controller: scroll,
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
          children: [
            Semantics(
              header: true,
              child: Text('At ${entry.time}, ${daysLabel(entry.days).toLowerCase()}',
                  style: Theme.of(ctx).textTheme.titleLarge),
            ),
            const SizedBox(height: 16),
            SceneEditor(initial: entry.settings, onChanged: (s) => entry.settings = s),
            const SizedBox(height: 20),
            FilledButton(onPressed: () => Navigator.pop(ctx), child: const Text('Done')),
          ],
        ),
      ),
    );
    if (mounted) setState(() {});
  }

  // --- curve -----------------------------------------------------------------

  List<Widget> _curveSection() {
    final scheme = Theme.of(context).colorScheme;
    final accent = accentForMode(_curve.operationalMode, scheme);
    final pts = [..._curve.points]..sort((a, b) => minutesOf(a.time).compareTo(minutesOf(b.time)));
    return [
      _Section(
        title: 'Through the day',
        child: CurveChart(points: _curve.points, accent: accent),
      ),
      _Section(
        title: 'Mode and fan',
        child: Column(
          children: [
            ModeSelector(
              value: _curve.operationalMode,
              onChanged: (m) => setState(() => _curve.operationalMode = m),
            ),
            const SizedBox(height: 8),
            FanControl(
              value: _curve.fanSpeed,
              accent: accent,
              onChanged: (f) => setState(() => _curve.fanSpeed = f),
            ),
          ],
        ),
      ),
      _Section(
        title: 'Points',
        trailing: '${pts.length}',
        child: Column(
          children: [
            for (final p in pts)
              _PointRow(
                key: ObjectKey(p),
                point: p,
                accent: accent,
                unit: AppScope.of(context).tempUnit,
                onPickTime: () async {
                  final t = await showTimePicker(context: context, initialTime: parseHHMM(p.time));
                  if (t != null) setState(() => p.time = hhmm(t));
                },
                onStep: (d) => setState(() {
                  p.temperature = snapHalf((p.temperature + d).clamp(kMinTemp, kMaxTemp));
                  Haptics.tick();
                }),
                onDelete: _curve.points.length <= 2
                    ? null
                    : () => setState(() => _curve.points.remove(p)),
              ),
            const SizedBox(height: 4),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () async {
                  final t = await showTimePicker(
                    context: context,
                    initialTime: const TimeOfDay(hour: 12, minute: 0),
                    helpText: 'A point at what time?',
                  );
                  if (t == null) return;
                  final at = hhmm(t);
                  setState(() => _curve.points.add(CurvePoint(
                        time: at,
                        // Where the line already is at that time, so adding a
                        // point changes nothing until it is moved.
                        temperature: snapHalf(curveAt(_curve.points, minutesOf(at))),
                      )));
                },
                icon: const Icon(Icons.add),
                label: const Text('Add a point'),
              ),
            ),
          ],
        ),
      ),
    ];
  }
}

TextStyle? _hint(BuildContext context) => Theme.of(context)
    .textTheme
    .bodySmall
    ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant);

// --- pieces -------------------------------------------------------------------

class _Heading extends StatelessWidget {
  const _Heading(this.title, {this.trailing});
  final String title;
  final String? trailing;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      header: true,
      child: Row(
        children: [
          Text(title.toUpperCase(),
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: scheme.primary,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.1,
                  )),
          const Spacer(),
          if (trailing != null)
            Text(trailing!, style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12)),
        ],
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.child, this.trailing});
  final String title;
  final String? trailing;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    // A Material, not a decorated box: switches and buttons inside draw their
    // ripples on the nearest Material, and a coloured box would hide them.
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Material(
        color: scheme.surfaceContainerLow,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.5)),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _Heading(title, trailing: trailing),
              const SizedBox(height: 12),
              child,
            ],
          ),
        ),
      ),
    );
  }
}

/// Favourite / Schedule / Curve as three tiles, icon over name. The name
/// shrinks to fit rather than wrapping: as a segmented button with icons,
/// narrow phones broke "Favourite" with its last letter on a line of its own.
class _KindPicker extends StatelessWidget {
  const _KindPicker({required this.value, required this.onChanged});
  final String value;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      container: true,
      label: 'Kind of program',
      child: Row(
        children: [
          for (final k in _kinds)
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: MergeSemantics(
                  child: Semantics(
                    button: true,
                    selected: k == value,
                    inMutuallyExclusiveGroup: true,
                    child: Material(
                      color: k == value ? scheme.primaryContainer : scheme.surfaceContainerHighest,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                        side: BorderSide(
                          color: k == value ? scheme.primary : Colors.transparent,
                          width: 1.5,
                        ),
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: InkWell(
                        onTap: () {
                          Haptics.select();
                          onChanged(k);
                        },
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(minHeight: 72),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 6),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(kindIcon(k),
                                    color: k == value
                                        ? scheme.onPrimaryContainer
                                        : scheme.onSurfaceVariant),
                                const SizedBox(height: 6),
                                FittedBox(
                                  fit: BoxFit.scaleDown,
                                  child: Text(
                                    kindName(k),
                                    maxLines: 1,
                                    softWrap: false,
                                    style: TextStyle(
                                      fontWeight: k == value ? FontWeight.w700 : FontWeight.w500,
                                      color: k == value
                                          ? scheme.onPrimaryContainer
                                          : scheme.onSurface,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _UnitPicker extends StatelessWidget {
  const _UnitPicker({required this.units, required this.selected, required this.onChanged});
  final List<UnitSummary> units;
  final Set<String> selected;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 4,
      children: [
        ChoiceChip(
          label: const Text('All units'),
          selected: selected.isEmpty,
          onSelected: (_) {
            selected.clear();
            onChanged();
          },
        ),
        for (final u in units)
          FilterChip(
            label: Text(u.name),
            selected: selected.contains(u.id),
            onSelected: (s) {
              s ? selected.add(u.id) : selected.remove(u.id);
              onChanged();
            },
          ),
      ],
    );
  }
}

class _EntryCard extends StatelessWidget {
  const _EntryCard({
    super.key,
    required this.entry,
    required this.onPickTime,
    required this.onDays,
    required this.onEditScene,
    required this.onDelete,
  });

  final ScheduleEntry entry;
  final VoidCallback onPickTime;
  final ValueChanged<List<int>> onDays;
  final VoidCallback onEditScene;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final on = entry.settings.powerState != false;
    final accent = on
        ? accentForMode(entry.settings.operationalMode ?? 'COOL', scheme)
        : scheme.outline;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
      color: scheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.5)),
      ),
      clipBehavior: Clip.antiAlias,
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // The scene's mode, as a stripe down the side: a glance down the
            // list says what each time does.
            Container(width: 6, color: accent),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(8, 8, 4, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Semantics(
                          button: true,
                          label: 'Time ${entry.time}, change',
                          excludeSemantics: true,
                          child: InkWell(
                            onTap: onPickTime,
                            borderRadius: BorderRadius.circular(12),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                              child: Text(
                                entry.time,
                                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                                  fontWeight: FontWeight.w600,
                                  fontFeatures: const [FontFeature.tabularFigures()],
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(daysLabel(entry.days),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(color: scheme.onSurfaceVariant)),
                        ),
                        IconButton(
                          tooltip: 'Delete the ${entry.time} time',
                          icon: const Icon(Icons.delete_outline),
                          onPressed: onDelete,
                        ),
                      ],
                    ),
                    _DayPicker(days: entry.days, onChanged: onDays),
                    const SizedBox(height: 10),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Expanded(child: SceneSummary(settings: entry.settings)),
                        TextButton.icon(
                          onPressed: onEditScene,
                          icon: const Icon(Icons.tune, size: 18),
                          label: const Text('Scene'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
      ),
    );
  }
}

/// Seven round day buttons, Monday first. None picked means every day.
class _DayPicker extends StatelessWidget {
  const _DayPicker({required this.days, required this.onChanged});
  final List<int> days;
  final ValueChanged<List<int>> onChanged;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final everyDay = days.isEmpty;
    // Each day takes a seventh of the row, so the touch target is as wide as
    // the card allows -- 48 or more on a phone like a Galaxy S25+ -- rather
    // than a fixed size that is too small on one phone and overflows another.
    return Row(
      children: [
        for (var d = 0; d < 7; d++)
          Expanded(
          child: Semantics(
            button: true,
            selected: days.contains(d),
            label: _weekdays[d],
            excludeSemantics: true,
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: () {
                Haptics.select();
                final next = {...days};
                next.contains(d) ? next.remove(d) : next.add(d);
                onChanged(next.toList()..sort());
              },
              child: SizedBox(
                height: 48,
                child: Center(
                  child: Container(
                    width: 36,
                    height: 36,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: days.contains(d)
                          ? scheme.primary
                          : everyDay
                              ? scheme.primary.withValues(alpha: 0.14)
                              : Colors.transparent,
                      border: Border.all(
                        color: days.contains(d) ? scheme.primary : scheme.outlineVariant,
                      ),
                    ),
                    child: Text(
                      _weekdays[d].substring(0, 2),
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        color: days.contains(d) ? scheme.onPrimary : scheme.onSurface,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          ),
      ],
    );
  }
}

class _PointRow extends StatelessWidget {
  const _PointRow({
    super.key,
    required this.point,
    required this.accent,
    required this.unit,
    required this.onPickTime,
    required this.onStep,
    required this.onDelete,
  });

  final CurvePoint point;
  final Color accent;
  final String unit;
  final VoidCallback onPickTime;
  final ValueChanged<double> onStep;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final ink = readableAccent(accent, scheme,
        on: layeredOnSurface(scheme, [scheme.surfaceContainerLow, accent.withValues(alpha: 0.16)]));
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          // The time takes whatever width the stepper leaves, and shrinks
          // rather than overflowing: at large text sizes a fixed chip pushed
          // the row 25 points off a Galaxy S25+'s screen.
          Expanded(
            child: Align(
              alignment: Alignment.centerLeft,
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Semantics(
                  button: true,
                  label: 'Point at ${point.time}, change the time',
                  excludeSemantics: true,
                  child: Material(
                    color: accent.withValues(alpha: 0.16),
                    shape: const StadiumBorder(),
                    clipBehavior: Clip.antiAlias,
                    child: InkWell(
                      onTap: onPickTime,
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(minHeight: 48),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.schedule, size: 18, color: ink),
                              const SizedBox(width: 6),
                              Text(point.time,
                                  style: TextStyle(
                                    fontWeight: FontWeight.w600,
                                    color: ink,
                                    fontFeatures: const [FontFeature.tabularFigures()],
                                  )),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          IconButton(
            tooltip: 'Lower the ${point.time} point',
            icon: const Icon(Icons.remove),
            onPressed: point.temperature <= kMinTemp ? null : () => onStep(-0.5),
          ),
          SizedBox(
            width: 56,
            child: Text(
              fmtTemp(point.temperature, unit, showUnit: false),
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
            ),
          ),
          IconButton(
            tooltip: 'Raise the ${point.time} point',
            icon: const Icon(Icons.add),
            onPressed: point.temperature >= kMaxTemp ? null : () => onStep(0.5),
          ),
          IconButton(
            tooltip: onDelete == null
                ? 'A curve needs two points'
                : 'Delete the ${point.time} point',
            icon: const Icon(Icons.delete_outline),
            onPressed: onDelete,
          ),
        ],
      ),
    );
  }
}
