import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../api_client.dart';
import '../app_scope.dart';
import '../home_widget_service.dart';
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
  bool _offline = false;     // server unreachable — show a banner, back off polling
  bool _noBatch = false;     // server predates /api/units/state — fall back to per-unit
  String? _error;
  Timer? _poll;

  static const _fastPoll = Duration(seconds: 5);
  static const _slowPoll = Duration(seconds: 20); // when offline

  ApiClient get _api => AppScope.of(context).api!;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadAll());
    _scheduleNext();
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  /// Self-rescheduling poll: fast normally, slow while the server is
  /// unreachable, so a down server doesn't hammer the radio every 5 s.
  void _scheduleNext() {
    _poll?.cancel();
    _poll = Timer(_offline ? _slowPoll : _fastPoll, () async {
      await _refreshStates();
      if (mounted) _scheduleNext();
    });
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

  /// Centralized error handling: re-pair on 401, flip the offline banner on
  /// a transport error, snackbar only for real errors the user triggered.
  Future<void> _handleErr(ApiException e, {bool silent = false}) async {
    if (!mounted) return;
    final controller = AppScope.of(context);
    final messenger = ScaffoldMessenger.of(context);
    if (e.unauthorized && !_reauthing) {
      _reauthing = true;
      await controller.handleUnauthorized();
      return;
    }
    if (e.status == 0) {
      if (mounted) setState(() => _offline = true);
      return;
    }
    if (!silent) messenger.showSnackBar(SnackBar(content: Text(e.message)));
  }

  /// Pull every unit's state. Prefers the one-shot batch endpoint; falls
  /// back to per-unit on servers older than 2.4.0. Returns true if the
  /// server was reachable (individual units may still be offline).
  /// Rethrows ApiException(401) so the caller re-pairs.
  Future<bool> _pullStates() async {
    if (!_noBatch) {
      try {
        final b = await _api.listStates();
        if (!mounted) return true;
        setState(() {
          for (final s in b.states) {
            _states[s.id] = s;
          }
          for (final e in b.errors) {
            final id = e['id'] as String;
            final prev = _states[id];
            _states[id] = prev != null
                ? prev.copyWith(online: false)
                : UnitState.offline(
                    id: id, name: (e['name'] ?? id) as String, ip: (e['ip'] ?? '') as String);
          }
        });
        return true;
      } on ApiException catch (e) {
        if (e.unauthorized) rethrow;
        if (e.status == 0) return false; // network
        if (e.status == 404) {
          _noBatch = true; // old server — fall through to per-unit
        } else {
          return false;
        }
      }
    }
    // Per-unit fallback (Breeze Core < 2.4.0).
    var reached = false;
    for (final u in _units) {
      if (_busy.contains(u.id)) continue;
      try {
        final s = await _api.getState(u.id);
        reached = true;
        if (mounted) setState(() => _states[u.id] = s);
      } on ApiException catch (e) {
        if (e.unauthorized) rethrow;
        if (e.status == 0) return reached;
      }
    }
    return reached || _units.isEmpty;
  }

  Future<void> _loadAll() async {
    setState(() { _loading = true; _error = null; });
    try {
      _units = await _api.listUnits();
      final ok = await _pullStates();
      if (mounted) {
        setState(() {
          _loading = false;
          _offline = !ok;
          _error = (!ok && _states.isEmpty) ? 'Could not load your units.' : null;
        });
      }
    } on ApiException catch (e) {
      await _handleErr(e);
      if (mounted) setState(() => _loading = false);
    }
    _syncWidgets();
  }

  Future<void> _refreshStates() async {
    if (_loading || _reauthing || !mounted) return;
    try {
      final ok = await _pullStates();
      if (mounted) setState(() => _offline = !ok);
    } on ApiException catch (e) {
      await _handleErr(e, silent: true); // background: banner only, no snackbar spam
    }
    _syncWidgets();
  }

  Future<void> _control(String id, ClimateSettings delta) async {
    final prev = _states[id];
    HapticFeedback.selectionClick();
    // Optimistic: reflect the change instantly, reconcile on the reply.
    if (prev != null) setState(() => _states[id] = prev.withDelta(delta));
    setState(() => _busy.add(id));
    try {
      final s = await _api.control(id, delta);
      if (mounted) setState(() => _states[id] = s);
    } on ApiException catch (e) {
      if (prev != null && mounted) setState(() => _states[id] = prev); // revert
      await _handleErr(e);
    } finally {
      if (mounted) setState(() => _busy.remove(id));
    }
    _syncWidgets();
  }

  /// Mirror the current units + states to the home-screen widgets (best-effort).
  void _syncWidgets() {
    if (_units.isEmpty) return;
    HomeWidgetService.sync(
      units: _units,
      states: _states,
      paired: _api.deviceToken != null,
    );
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

  Future<void> _removeUnit(String id, String name) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove unit'),
        content: Text('Remove "$name" from the server? You can add it back later by IP.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Remove')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final done = await _guard(() => _api.deleteUnit(id));
    if (done && mounted) {
      setState(() => _states.remove(id));
      await _loadAll();
    }
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
        _scheduleNext();
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
      body: Column(
        children: [
          if (_offline) _offlineBar(context),
          Expanded(
            child: RefreshIndicator(onRefresh: _loadAll, child: _buildBody()),
          ),
        ],
      ),
    );
  }

  Widget _offlineBar(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.errorContainer,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          children: [
            Icon(Icons.cloud_off, size: 18, color: scheme.onErrorContainer),
            const SizedBox(width: 10),
            Expanded(
              child: Text('Can’t reach the server — retrying…',
                  style: TextStyle(color: scheme.onErrorContainer)),
            ),
            TextButton(onPressed: _loadAll, child: const Text('Retry')),
          ],
        ),
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
                      onRemove: () => _removeUnit(u.id, s.name),
                    ),
            ),
          ),
        );
      },
    );
  }
}
