import 'package:flutter/material.dart';

import '../api_client.dart';
import '../app_scope.dart';
import '../models.dart';
import '../theme.dart';
import '../util.dart';
import '../widgets/climate_settings_editor.dart';
import '../widgets/curve_painter.dart';

class ProgramEditScreen extends StatefulWidget {
  final List<UnitSummary> units;
  final Program? existing;
  const ProgramEditScreen({super.key, required this.units, this.existing});
  @override
  State<ProgramEditScreen> createState() => _ProgramEditScreenState();
}

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
    _favourite = e?.favourite?.copy() ??
        ClimateSettings(
            powerState: true,
            operationalMode: 'COOL',
            targetTemperature: 22.0,
            fanSpeed: 102,
            swingMode: 'OFF',
            eco: false,
            turbo: false);
    _schedule = e?.schedule.map((s) => ScheduleEntry(days: [...s.days], time: s.time, settings: s.settings.copy())).toList() ?? [];
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
      _snack('Add at least one schedule entry.');
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
      if (mounted) Navigator.pop(context, true);
    } on ApiException catch (e) {
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
          IconButton(
            icon: _saving
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.check),
            onPressed: _saving ? null : _save,
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(
            controller: _name,
            decoration: const InputDecoration(labelText: 'Name', border: OutlineInputBorder()),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Enabled'),
            value: _enabled,
            onChanged: (v) => setState(() => _enabled = v),
          ),
          const SizedBox(height: 8),
          Text('Applies to', style: Theme.of(context).textTheme.labelLarge),
          const SizedBox(height: 4),
          Wrap(
            spacing: 8,
            children: widget.units
                .map((u) => FilterChip(
                      label: Text(u.name),
                      selected: _units.contains(u.id),
                      onSelected: (s) => setState(() {
                        if (s) {
                          _units.add(u.id);
                        } else {
                          _units.remove(u.id);
                        }
                      }),
                    ))
                .toList(),
          ),
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              _units.isEmpty ? 'None selected → every unit' : '${_units.length} selected',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
          const SizedBox(height: 16),
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'favourite', label: Text('Favourite'), icon: Icon(Icons.star_outline)),
              ButtonSegment(value: 'schedule', label: Text('Schedule'), icon: Icon(Icons.calendar_month)),
              ButtonSegment(value: 'curve', label: Text('Curve'), icon: Icon(Icons.show_chart)),
            ],
            selected: {_kind},
            onSelectionChanged: (s) => setState(() => _kind = s.first),
          ),
          const SizedBox(height: 16),
          if (_kind == 'favourite') _buildFavourite(),
          if (_kind == 'schedule') _buildSchedule(),
          if (_kind == 'curve') _buildCurve(),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  Widget _buildFavourite() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('A saved scene you apply on demand (or reference from the app).',
            style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(height: 8),
        ClimateSettingsEditor(initial: _favourite, onChanged: (s) => _favourite = s),
      ],
    );
  }

  Widget _buildSchedule() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Each entry applies its scene at a time on the chosen days '
            '(server local time).', style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(height: 8),
        for (final entry in _schedule)
          Card(
            key: ObjectKey(entry),
            margin: const EdgeInsets.symmetric(vertical: 6),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Wrap(
                          spacing: 6,
                          children: [
                            for (var d = 0; d < 7; d++)
                              FilterChip(
                                label: Text(kWeekdayShort[d]),
                                selected: entry.days.contains(d),
                                onSelected: (s) => setState(() {
                                  if (s) {
                                    entry.days.add(d);
                                  } else {
                                    entry.days.remove(d);
                                  }
                                  entry.days.sort();
                                }),
                              ),
                          ],
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.delete_outline),
                        onPressed: () => setState(() => _schedule.remove(entry)),
                      ),
                    ],
                  ),
                  if (entry.days.isEmpty)
                    Text('every day', style: Theme.of(context).textTheme.bodySmall),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.access_time),
                    title: Text('Time: ${entry.time}'),
                    onTap: () async {
                      final t = await showTimePicker(
                          context: context, initialTime: parseHHMM(entry.time));
                      if (t != null) setState(() => entry.time = hhmm(t));
                    },
                  ),
                  ExpansionTile(
                    tilePadding: EdgeInsets.zero,
                    title: const Text('Scene'),
                    childrenPadding: const EdgeInsets.only(bottom: 8),
                    children: [
                      ClimateSettingsEditor(
                        initial: entry.settings,
                        onChanged: (s) => entry.settings = s,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: () => setState(() => _schedule.add(ScheduleEntry(
                days: [],
                time: '07:00',
                settings: ClimateSettings(
                    powerState: true,
                    operationalMode: 'COOL',
                    targetTemperature: 22.0,
                    fanSpeed: 102,
                    swingMode: 'OFF',
                    eco: false,
                    turbo: false),
              ))),
          icon: const Icon(Icons.add),
          label: const Text('Add entry'),
        ),
      ],
    );
  }

  Widget _buildCurve() {
    final accent = accentForMode(_curve.operationalMode, Theme.of(context).colorScheme);
    final pts = [..._curve.points]..sort((a, b) => minutesOf(a.time).compareTo(minutesOf(b.time)));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('The setpoint follows this curve through the day; the server '
            'continuously adjusts it (server local time).',
            style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(height: 12),
        CurveChart(points: _curve.points, accent: accent),
        const SizedBox(height: 12),
        Text('Base mode', style: Theme.of(context).textTheme.labelLarge),
        Wrap(
          spacing: 8,
          children: kModes
              .map((m) => ChoiceChip(
                    label: Text(kModeLabels[m]!),
                    selected: _curve.operationalMode == m,
                    onSelected: (_) => setState(() => _curve.operationalMode = m),
                  ))
              .toList(),
        ),
        const SizedBox(height: 8),
        Text('Fan', style: Theme.of(context).textTheme.labelLarge),
        Wrap(
          spacing: 8,
          children: kFanSpeeds
              .map((f) => ChoiceChip(
                    label: Text(kFanLabels[f]!),
                    selected: _curve.fanSpeed == f,
                    onSelected: (_) => setState(() => _curve.fanSpeed = f),
                  ))
              .toList(),
        ),
        const SizedBox(height: 12),
        Text('Points', style: Theme.of(context).textTheme.labelLarge),
        for (final p in pts)
          Card(
            key: ObjectKey(p),
            margin: const EdgeInsets.symmetric(vertical: 4),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              child: Row(
                children: [
                  TextButton.icon(
                    icon: const Icon(Icons.access_time, size: 18),
                    label: Text(p.time),
                    onPressed: () async {
                      final t = await showTimePicker(
                          context: context, initialTime: parseHHMM(p.time));
                      if (t != null) setState(() => p.time = hhmm(t));
                    },
                  ),
                  Expanded(
                    child: Slider(
                      min: kMinTemp,
                      max: kMaxTemp,
                      divisions: ((kMaxTemp - kMinTemp) * 2).round(),
                      value: p.temperature.clamp(kMinTemp, kMaxTemp),
                      label: '${p.temperature.toStringAsFixed(1)}°',
                      onChanged: (v) => setState(() => p.temperature = (v * 2).round() / 2),
                    ),
                  ),
                  SizedBox(width: 44, child: Text('${p.temperature.toStringAsFixed(1)}°')),
                  IconButton(
                    icon: const Icon(Icons.delete_outline),
                    onPressed: _curve.points.length <= 1
                        ? null
                        : () => setState(() => _curve.points.remove(p)),
                  ),
                ],
              ),
            ),
          ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: () => setState(() => _curve.points.add(CurvePoint(time: '12:00', temperature: 22.0))),
          icon: const Icon(Icons.add),
          label: const Text('Add point'),
        ),
      ],
    );
  }
}
