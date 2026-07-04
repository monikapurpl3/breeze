import 'package:flutter/material.dart';

import '../api_client.dart';
import '../app_scope.dart';
import '../models.dart';
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

  IconData _kindIcon(String kind) => switch (kind) {
        'schedule' => Icons.calendar_month,
        'curve' => Icons.show_chart,
        _ => Icons.star_outline,
      };

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
    if (_programs.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: Text('No programs yet.\nTap “New” to add a favourite, schedule or curve.',
              textAlign: TextAlign.center),
        ),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.only(bottom: 88),
      itemCount: _programs.length,
      itemBuilder: (context, i) {
        final p = _programs[i];
        return Card(
          margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
          child: ListTile(
            leading: Icon(_kindIcon(p.kind)),
            title: Text(p.name),
            subtitle: Text('${p.kind} · ${_target(p)}'),
            onTap: () => _edit(p),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Switch(value: p.enabled, onChanged: (v) => _toggle(p, v)),
                PopupMenuButton<String>(
                  onSelected: (v) {
                    if (v == 'apply') _apply(p);
                    if (v == 'edit') _edit(p);
                    if (v == 'delete') _delete(p);
                  },
                  itemBuilder: (_) => [
                    if (p.kind != 'schedule')
                      const PopupMenuItem(value: 'apply', child: Text('Apply now')),
                    const PopupMenuItem(value: 'edit', child: Text('Edit')),
                    const PopupMenuItem(value: 'delete', child: Text('Delete')),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
