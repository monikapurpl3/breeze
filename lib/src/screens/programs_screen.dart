import 'package:flutter/material.dart';

import '../api_client.dart';
import '../app_scope.dart';
import '../models.dart';
import '../theme.dart';
import '../util.dart';
import '../widgets/curve_painter.dart';
import '../widgets/scene_editor.dart';
import 'program_edit_screen.dart';

class ProgramsScreen extends StatefulWidget {
  final List<UnitSummary> units;
  const ProgramsScreen({super.key, required this.units});
  @override
  State<ProgramsScreen> createState() => _ProgramsScreenState();
}

class _ProgramsScreenState extends State<ProgramsScreen> {
  List<Program> _programs = [];
  bool _loading = true;
  bool _unsupported = false;
  String? _error;

  ApiClient get _api => AppScope.of(context).api!;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final p = await _api.listPrograms();
      if (mounted) setState(() { _programs = p; _loading = false; });
    } on ApiException catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _unsupported = e.status == 404;
          _error = _unsupported ? null : e.message;
        });
      }
    }
  }

  String _target(Program p) {
    if (p.unitIds.isEmpty) return 'All units';
    final names = p.unitIds
        .map((id) => widget.units.firstWhere(
              (u) => u.id == id,
              orElse: () => UnitSummary(id: id, name: id, ip: ''),
            ).name)
        .join(', ');
    return names;
  }

  Future<void> _toggle(Program p, bool value) async {
    p.enabled = value;
    setState(() {});
    try {
      await _api.updateProgram(p);
    } on ApiException catch (e) {
      if (mounted) {
        p.enabled = !value;
        setState(() {});
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
      }
    }
  }

  Future<void> _apply(Program p) async {
    try {
      await _api.applyProgram(p.id);
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Applied “${p.name}”')));
      }
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
      }
    }
  }

  Future<void> _delete(Program p) async {
    try {
      await _api.deleteProgram(p.id);
      await _load();
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
      }
    }
  }

  Future<void> _edit(Program? p) async {
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => ProgramEditScreen(units: widget.units, existing: p)),
    );
    if (saved == true) _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Programs')),
      floatingActionButton: _unsupported
          ? null
          : FloatingActionButton.extended(
              onPressed: () => _edit(null),
              icon: const Icon(Icons.add),
              label: const Text('New'),
            ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_unsupported) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: Text(
            'This server doesn’t have the programs feature yet.\n\n'
            'Update the server, then favourites, schedules and '
            'temperature curves will appear here.',
            textAlign: TextAlign.center,
          ),
        ),
      );
    }
    if (_error != null) {
      return Center(child: Text(_error!));
    }
    if (_programs.isEmpty) return _Empty(onNew: () => _edit(null));
    final unit = AppScope.of(context).tempUnit;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 96),
      children: [
        for (final kind in const ['favourite', 'schedule', 'curve'])
          if (_programs.any((p) => p.kind == kind)) ...[
            _GroupHeading(
              kind == 'favourite'
                  ? 'Favourites'
                  : kind == 'schedule'
                      ? 'Schedules'
                      : 'Curves',
              count: _programs.where((p) => p.kind == kind).length,
            ),
            for (final p in _programs.where((p) => p.kind == kind))
              _ProgramCard(
                program: p,
                units: _target(p),
                unit: unit,
                onTap: () => _edit(p),
                onToggle: (v) => _toggle(p, v),
                onApply: () => _apply(p),
                onDelete: () => _confirmDelete(p),
              ),
          ],
      ],
    );
  }

  Future<void> _confirmDelete(Program p) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Delete “${p.name}”?'),
        content: const Text('It is removed from the server, for every phone.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Delete')),
        ],
      ),
    );
    if (ok == true) await _delete(p);
  }
}

class _GroupHeading extends StatelessWidget {
  const _GroupHeading(this.title, {required this.count});
  final String title;
  final int count;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      header: true,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(4, 16, 4, 8),
        child: Text('${title.toUpperCase()}  ·  $count',
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: scheme.primary,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.1,
                )),
      ),
    );
  }
}

/// One program: a tile in its mode's colour, its name, what it does in a
/// line, and where -- with Apply for a favourite and on/off for the rest.
class _ProgramCard extends StatelessWidget {
  const _ProgramCard({
    required this.program,
    required this.units,
    required this.unit,
    required this.onTap,
    required this.onToggle,
    required this.onApply,
    required this.onDelete,
  });

  final Program program;
  final String units;
  final String unit;
  final VoidCallback onTap;
  final ValueChanged<bool> onToggle;
  final VoidCallback onApply;
  final VoidCallback onDelete;

  /// The mode that colours it: the favourite's, the curve's, or a
  /// schedule's first scene that switches a unit on.
  String _mode() {
    switch (program.kind) {
      case 'favourite':
        return program.favourite?.operationalMode ?? 'COOL';
      case 'curve':
        return program.curve?.operationalMode ?? 'COOL';
      default:
        for (final e in program.schedule) {
          if (e.settings.powerState != false && e.settings.operationalMode != null) {
            return e.settings.operationalMode!;
          }
        }
        return 'COOL';
    }
  }

  String _summary() {
    switch (program.kind) {
      case 'favourite':
        return program.favourite == null
            ? 'Empty scene'
            : SceneSummary.describe(program.favourite!, unit);
      case 'schedule':
        final entries = [...program.schedule]
          ..sort((a, b) => minutesOf(a.time).compareTo(minutesOf(b.time)));
        if (entries.isEmpty) return 'No times';
        return entries
            .map((e) => '${e.time} ${e.settings.powerState == false ? 'off' : 'on'}')
            .join(' · ');
      default:
        final pts = program.curve?.points ?? const <CurvePoint>[];
        if (pts.isEmpty) return 'No points';
        final temps = pts.map((p) => p.temperature);
        final lo = temps.reduce((a, b) => a < b ? a : b);
        final hi = temps.reduce((a, b) => a > b ? a : b);
        return '${kModeLabels[program.curve!.operationalMode] ?? ''} · '
            '${fmtTemp(lo, unit, showUnit: false)} to ${fmtTemp(hi, unit, showUnit: false)}';
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final accent = accentForMode(_mode(), scheme);
    final dim = program.kind != 'favourite' && !program.enabled;
    final ink = readableAccent(accent, scheme,
        on: layeredOnSurface(scheme, [scheme.surfaceContainerLow, accent.withValues(alpha: 0.18)]));
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: scheme.surfaceContainerLow,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.5)),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 4, 12),
            child: Row(
              children: [
                Opacity(
                  opacity: dim ? 0.5 : 1,
                  child: Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: accent.withValues(alpha: 0.18),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Icon(kindIcon(program.kind), color: ink),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Opacity(
                    opacity: dim ? 0.6 : 1,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(program.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context)
                                .textTheme
                                .titleMedium
                                ?.copyWith(fontWeight: FontWeight.w600)),
                        const SizedBox(height: 2),
                        if (program.kind == 'curve' && (program.curve?.points.isNotEmpty ?? false))
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 3),
                            child: SizedBox(
                              width: 120,
                              child: CurveChart(
                                points: program.curve!.points,
                                accent: accent,
                                height: 22,
                                compact: true,
                              ),
                            ),
                          ),
                        Text(_summary(),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 13)),
                        const SizedBox(height: 2),
                        Row(
                          children: [
                            Icon(Icons.home_outlined, size: 14, color: scheme.onSurfaceVariant),
                            const SizedBox(width: 4),
                            Expanded(
                              child: Text(units,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12.5)),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                if (program.kind == 'favourite')
                  IconButton.filledTonal(
                    tooltip: 'Apply ${program.name} now',
                    icon: const Icon(Icons.play_arrow_rounded),
                    onPressed: onApply,
                  )
                else
                  // Named after its program: a list of bare "switch, on" said
                  // nothing about which program each one ran.
                  MergeSemantics(
                    child: Semantics(
                      label: 'Running, ${program.name}',
                      child: Switch(value: program.enabled, onChanged: onToggle),
                    ),
                  ),
                PopupMenuButton<String>(
                  tooltip: 'More options for ${program.name}',
                  onSelected: (v) {
                    if (v == 'apply') onApply();
                    if (v == 'edit') onTap();
                    if (v == 'delete') onDelete();
                  },
                  itemBuilder: (_) => [
                    if (program.kind == 'curve')
                      const PopupMenuItem(value: 'apply', child: Text('Apply now')),
                    const PopupMenuItem(value: 'edit', child: Text('Edit')),
                    const PopupMenuItem(value: 'delete', child: Text('Delete')),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty({required this.onNew});
  final VoidCallback onNew;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    Widget row(String kind, String text) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: scheme.primaryContainer,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(kindIcon(kind), color: scheme.onPrimaryContainer, size: 22),
              ),
              const SizedBox(width: 14),
              Expanded(child: Text(text)),
            ],
          ),
        );
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('No programs yet', style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 16),
            row('favourite', 'A favourite: a scene you apply with one tap.'),
            row('schedule', 'A schedule: scenes at times of the week, run by the server.'),
            row('curve', 'A curve: a temperature that follows the day.'),
            const SizedBox(height: 20),
            FilledButton.icon(
                onPressed: onNew, icon: const Icon(Icons.add), label: const Text('New program')),
          ],
        ),
      ),
    );
  }
}
