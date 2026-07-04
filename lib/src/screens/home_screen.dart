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
                    ),
            ),
          ),
        );
      },
    );
  }
}
