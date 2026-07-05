import 'dart:async';

import 'package:flutter/material.dart';

import '../api_client.dart';
import '../app_scope.dart';
import '../models.dart';
import '../widgets/unit_card.dart';
import 'diagnostics_screen.dart';
import 'programs_screen.dart';
import 'settings_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  List<UnitSummary> _units = [];
  final Map<String, UnitState> _states = {};
  final Set<String> _busy = {};
  bool _loading = true;
  bool _reauthing = false;
  String? _error;
  Timer? _poll;

  ApiClient get _api => AppScope.of(context).api!;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadAll());
    _poll = Timer.periodic(const Duration(seconds: 5), (_) => _refreshStates());
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  Future<bool> _guard(Future<void> Function() body) async {
    // Capture context-bound objects before any await to avoid using
    // BuildContext across async gaps.
    final controller = AppScope.of(context);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await body();
      return true;
    } on ApiException catch (e) {
      if (e.unauthorized && !_reauthing) {
        _reauthing = true;
        await controller.handleUnauthorized();
      } else {
        messenger.showSnackBar(SnackBar(content: Text(e.message)));
      }
      return false;
    }
  }

  Future<void> _loadAll() async {
    setState(() { _loading = true; _error = null; });
    final ok = await _guard(() async {
      _units = await _api.listUnits();
      for (final u in _units) {
        _states[u.id] = await _api.getState(u.id);
      }
    });
    if (mounted) {
      setState(() {
        _loading = false;
        if (!ok && _states.isEmpty) _error = 'Could not load your units.';
      });
    }
  }

  Future<void> _refreshStates() async {
    if (_loading || _reauthing || !mounted) return;
    for (final u in _units) {
      if (_busy.contains(u.id)) continue;
      await _guard(() async {
        final s = await _api.getState(u.id);
        if (mounted) setState(() => _states[u.id] = s);
      });
      if (_reauthing) return;
    }
  }

  Future<void> _control(String id, ClimateSettings delta) async {
    setState(() => _busy.add(id));
    await _guard(() async {
      final s = await _api.control(id, delta);
      if (mounted) setState(() => _states[id] = s);
    });
    if (mounted) setState(() => _busy.remove(id));
  }

  Future<void> _rename(String id, String current) async {
    final ctrl = TextEditingController(text: current);
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Rename unit'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          maxLength: 64,
          decoration: const InputDecoration(labelText: 'Name'),
          onSubmitted: (v) => Navigator.pop(ctx, v.trim()),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, ctrl.text.trim()), child: const Text('Save')),
        ],
      ),
    );
    if (name == null || name.isEmpty || name == current) return;
    final ok = await _guard(() => _api.renameUnit(id, name));
    if (ok && mounted) await _loadAll();
  }

  Future<void> _addByIp() async {
    final ipC = TextEditingController();
    final nameC = TextEditingController();
    final go = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Add unit by IP'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: ipC,
              autofocus: true,
              keyboardType: TextInputType.visiblePassword, // shows digits+dots, no autocorrect
              decoration: const InputDecoration(labelText: 'Unit IP address', hintText: '192.168.1.73'),
            ),
            TextField(
              controller: nameC,
              maxLength: 64,
              decoration: const InputDecoration(labelText: 'Name (optional)'),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Add')),
        ],
      ),
    );
    if (go != true) return;
    final ip = ipC.text.trim();
    if (ip.isEmpty || !mounted) return;
    final name = nameC.text.trim();
    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(const SnackBar(content: Text('Discovering unit…')));
    final ok = await _guard(() async {
      final u = await _api.addUnitByIp(ip, name.isEmpty ? null : name);
      messenger.showSnackBar(SnackBar(content: Text('Added "${u['name']}"')));
    });
    if (ok && mounted) await _loadAll();
  }

  void _open(Widget screen) {
    _poll?.cancel(); // pause polling while away; resume on return
    Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => screen))
        .then((_) {
      if (mounted) {
        _poll = Timer.periodic(const Duration(seconds: 5), (_) => _refreshStates());
        _loadAll();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Breeze'),
        actions: [
          IconButton(
            tooltip: 'Add unit by IP',
            icon: const Icon(Icons.add),
            onPressed: _addByIp,
          ),
          IconButton(
            tooltip: 'Programs',
            icon: const Icon(Icons.schedule),
            onPressed: () => _open(ProgramsScreen(units: _units)),
          ),
          IconButton(
            tooltip: 'Diagnostics',
            icon: const Icon(Icons.troubleshoot),
            onPressed: () => _open(const DiagnosticsScreen()),
          ),
          IconButton(
            tooltip: 'Settings',
            icon: const Icon(Icons.settings_outlined),
            onPressed: () => _open(const SettingsScreen()),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _loadAll,
        child: _buildBody(),
      ),
    );
  }

  Widget _buildBody() {
    if (_loading && _states.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null && _states.isEmpty) {
      return ListView(children: [
        const SizedBox(height: 120),
        Center(child: Text(_error!)),
        const SizedBox(height: 12),
        Center(child: FilledButton(onPressed: _loadAll, child: const Text('Retry'))),
      ]);
    }
    if (_units.isEmpty) {
      return ListView(children: const [
        SizedBox(height: 120),
        Center(child: Text('No units configured on the server.')),
      ]);
    }
    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: _units.length,
      itemBuilder: (context, i) {
        final u = _units[i];
        final s = _states[u.id];
        return Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              child: s == null
                  ? Card(
                      child: ListTile(
                        leading: const SizedBox(
                            width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
                        title: Text(u.name),
                        subtitle: const Text('connecting…'),
                      ),
                    )
                  : UnitCard(
                      state: s,
                      busy: _busy.contains(u.id),
                      onControl: (delta) => _control(u.id, delta),
                      onRename: () => _rename(u.id, s.name),
                    ),
            ),
          ),
        );
      },
    );
  }
}
