import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../api_client.dart';
import '../app_scope.dart';
import '../home_widget_service.dart';
import '../models.dart';
import 'diagnostics_screen.dart';
import 'programs_screen.dart';
import 'settings_screen.dart';
import 'unit_page.dart';

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

  final PageController _pageController = PageController();
  int _page = 0;

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
    _pageController.dispose();
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
    final controller = AppScope.of(context);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await body();
      return true;
    } on ApiException catch (e) {
      if (e.unauthorized && !_reauthing) {
        _reauthing = true;
        await controller.handleUnauthorized();
      } else if (e.upgradeRequired) {
        if (!await controller.attemptUpgrade()) {
          messenger.showSnackBar(SnackBar(content: Text(e.message)));
        }
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
    if (e.upgradeRequired) {
      final ok = await controller.attemptUpgrade();
      if (!ok && !silent) messenger.showSnackBar(SnackBar(content: Text(e.message)));
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
  /// server was reachable. Rethrows ApiException(401) so the caller re-pairs.
  /// Merges into _states in place — never clears — so the UI doesn't flicker.
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
          if (_page >= _units.length) _page = _units.isEmpty ? 0 : _units.length - 1;
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
    // Silent background poll — no visible spinner (states just update in
    // place). The discreet indicator is reserved for user-initiated actions.
    try {
      final ok = await _pullStates();
      if (mounted) setState(() => _offline = !ok);
    } on ApiException catch (e) {
      await _handleErr(e, silent: true); // background: banner only, no snackbar spam
    }
    _syncWidgets();
  }

  Future<void> _control(String id, ClimateSettings delta) async {
    // The beep preference rides on every command (server default is silent).
    delta.beep = AppScope.of(context).beep;
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

  void _syncWidgets() {
    if (_units.isEmpty) return;
    HomeWidgetService.sync(
      units: _units,
      states: _states,
      paired: _api.hasDeviceCredential,
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
        content: Text('Remove "$name" from the server? You can add it back later.'),
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

  // ---- adding units: scan or manual --------------------------------------

  Future<void> _addUnit() async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.wifi_find),
              title: const Text('Scan the network'),
              subtitle: const Text('Find units by looking for open AC ports'),
              onTap: () => Navigator.pop(ctx, 'scan'),
            ),
            ListTile(
              leading: const Icon(Icons.keyboard),
              title: const Text('Enter IP address'),
              subtitle: const Text('Add a unit manually by its LAN IP'),
              onTap: () => Navigator.pop(ctx, 'ip'),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (choice == 'scan') {
      await _scanAndAdd();
    } else if (choice == 'ip') {
      await _addByIp();
    }
  }

  Future<void> _scanAndAdd() async {
    if (!mounted) return;
    final knownIps = {for (final s in _states.values) s.ip};
    final ip = await showDialog<String>(
      context: context,
      builder: (_) => _ScanDialog(api: _api, knownIps: knownIps),
    );
    if (ip == null || ip == '__manual__') {
      if (ip == '__manual__') await _addByIp(prefillIp: null);
      return;
    }
    await _addResolvedIp(ip, null);
  }

  Future<void> _addByIp({String? prefillIp}) async {
    final ipC = TextEditingController(text: prefillIp ?? '');
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
              keyboardType: TextInputType.visiblePassword,
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
    if (ip.isEmpty) return;
    await _addResolvedIp(ip, nameC.text.trim());
  }

  Future<void> _addResolvedIp(String ip, String? name) async {
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(const SnackBar(content: Text('Discovering unit…')));
    final ok = await _guard(() async {
      final u = await _api.addUnitByIp(ip, (name == null || name.isEmpty) ? null : name);
      messenger.showSnackBar(SnackBar(content: Text('Added "${u['name']}"')));
    });
    if (ok && mounted) await _loadAll();
  }

  void _open(Widget screen) {
    _poll?.cancel(); // pause polling while away; resume on return
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen)).then((_) {
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
            tooltip: 'Add unit',
            icon: const Icon(Icons.add),
            onPressed: _addUnit,
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
      body: SafeArea(
        child: Column(
          children: [
            if (_offline) _offlineBar(context),
            Expanded(child: _buildBody()),
          ],
        ),
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
      return _CenteredMessage(
        text: _error!,
        action: FilledButton(onPressed: _loadAll, child: const Text('Retry')),
      );
    }
    if (_units.isEmpty) {
      return _CenteredMessage(
        text: 'No units yet.',
        action: FilledButton.icon(
          onPressed: _addUnit,
          icon: const Icon(Icons.add),
          label: const Text('Add a unit'),
        ),
      );
    }
    return Column(
      children: [
        Expanded(
          child: PageView.builder(
            controller: _pageController,
            itemCount: _units.length,
            onPageChanged: (i) => setState(() => _page = i),
            itemBuilder: (context, i) {
              final u = _units[i];
              final s = _states[u.id];
              if (s == null) {
                return Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const CircularProgressIndicator(strokeWidth: 2),
                      const SizedBox(height: 12),
                      Text('Connecting to ${u.name}…'),
                    ],
                  ),
                );
              }
              return UnitPage(
                key: ValueKey(u.id),
                state: s,
                // Discreet indicator only while a user-initiated command for
                // this unit is in flight — never during idle background polls.
                refreshing: _busy.contains(u.id),
                onControl: (delta) => _control(u.id, delta),
                onRename: () => _rename(u.id, s.name),
                onRemove: () => _removeUnit(u.id, s.name),
              );
            },
          ),
        ),
        if (_units.length > 1) _dots(context),
      ],
    );
  }

  Widget _dots(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10, top: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          for (var i = 0; i < _units.length; i++)
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              margin: const EdgeInsets.symmetric(horizontal: 3),
              width: i == _page ? 22 : 8,
              height: 8,
              decoration: BoxDecoration(
                color: i == _page ? scheme.primary : scheme.onSurfaceVariant.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(4),
              ),
            ),
        ],
      ),
    );
  }
}

class _CenteredMessage extends StatelessWidget {
  const _CenteredMessage({required this.text, this.action});
  final String text;
  final Widget? action;
  @override
  Widget build(BuildContext context) => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(text, textAlign: TextAlign.center),
            if (action != null) ...[const SizedBox(height: 16), action!],
          ],
        ),
      );
}

/// Scan dialog: runs GET /api/units/scan and lists candidates. Tapping an
/// un-added candidate returns its IP; the caller adds it (which runs real
/// discovery). Falls back to manual entry on older servers.
class _ScanDialog extends StatefulWidget {
  const _ScanDialog({required this.api, required this.knownIps});
  final ApiClient api;
  final Set<String> knownIps;

  @override
  State<_ScanDialog> createState() => _ScanDialogState();
}

class _ScanDialogState extends State<_ScanDialog> {
  bool _loading = true;
  String? _error;
  bool _tooOld = false;
  List<Map<String, dynamic>> _found = const [];

  @override
  void initState() {
    super.initState();
    _run();
  }

  Future<void> _run() async {
    setState(() { _loading = true; _error = null; });
    try {
      final c = await widget.api.scanUnits();
      if (mounted) setState(() { _found = c; _loading = false; });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        if (e.status == 404) {
          _tooOld = true;
        } else {
          _error = e.message;
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return AlertDialog(
      title: const Text('Scan for units'),
      content: SizedBox(
        width: 320,
        child: _body(scheme),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, '__manual__'),
          child: const Text('Enter IP instead'),
        ),
        if (!_loading)
          TextButton(onPressed: _run, child: const Text('Rescan')),
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close')),
      ],
    );
  }

  Widget _body(ColorScheme scheme) {
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('Scanning the network…'),
          ],
        ),
      );
    }
    if (_tooOld) {
      return const Text(
          'This server is older than 3.0 and can’t scan. Add the unit by its IP instead.');
    }
    if (_error != null) {
      return Text('Scan failed: $_error');
    }
    if (_found.isEmpty) {
      return const Text('No units found. Make sure they’re powered on and on this network, '
          'or add one by its IP.');
    }
    return ClipRect(
      child: ListView(
        shrinkWrap: true,
        children: [
          for (final c in _found)
            _candidateTile(scheme, c),
        ],
      ),
    );
  }

  Widget _candidateTile(ColorScheme scheme, Map<String, dynamic> c) {
    final ip = c['ip'] as String;
    final port = c['port'];
    final known = (c['known'] as bool?) ?? widget.knownIps.contains(ip);
    return ListTile(
      leading: Icon(known ? Icons.check_circle : Icons.ac_unit,
          color: known ? scheme.primary : scheme.onSurfaceVariant),
      title: Text(ip),
      subtitle: Text(known ? 'already added' : 'port $port open'),
      enabled: !known,
      onTap: known ? null : () => Navigator.pop(context, ip),
    );
  }
}
