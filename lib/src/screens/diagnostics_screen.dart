import 'package:flutter/material.dart';

import '../api_client.dart';
import '../app_scope.dart';
import '../models.dart';

enum _Level { ok, warn, fail, info }

class _Check {
  final _Level level;
  final String label;
  final String detail;
  _Check(this.level, this.label, this.detail);
}

class DiagnosticsScreen extends StatefulWidget {
  const DiagnosticsScreen({super.key});
  @override
  State<DiagnosticsScreen> createState() => _DiagnosticsScreenState();
}

class _DiagnosticsScreenState extends State<DiagnosticsScreen> {
  final List<_Check> _results = [];
  bool _running = false;

  ApiClient get _api => AppScope.of(context).api!;

  void _add(_Level l, String label, String detail) {
    if (mounted) setState(() => _results.add(_Check(l, label, detail)));
  }

  Future<void> _run() async {
    setState(() { _running = true; _results.clear(); });

    // 1. connectivity
    List<UnitSummary> units = [];
    try {
      final sw = Stopwatch()..start();
      units = await _api.listUnits();
      sw.stop();
      _add(_Level.ok, 'Server reachable', '${units.length} unit(s) · ${sw.elapsedMilliseconds} ms');
    } on ApiException catch (e) {
      _add(_Level.fail, 'Server unreachable', e.message);
      if (mounted) setState(() => _running = false);
      return;
    }

    // 2. scheduler
    try {
      final st = await _api.schedulerStatus();
      final running = st['running'] == true;
      _add(running ? _Level.ok : _Level.warn, 'Scheduler',
          'running=${st['running']} · runs=${st['runs']} · last=${st['last_run'] ?? '—'}');
    } on ApiException catch (e) {
      _add(e.status == 404 ? _Level.warn : _Level.info, 'Scheduler',
          e.status == 404 ? 'server has no programs feature yet (update it)' : e.message);
    }

    // 3. per-unit
    for (final u in units) {
      UnitState? state;
      try {
        state = await _api.getState(u.id);
        _add(_Level.ok, '${u.name}: state', 'fetched OK');
      } on ApiException catch (e) {
        _add(_Level.fail, '${u.name}: state', e.message);
        continue;
      }

      _add(state.online ? _Level.ok : _Level.warn, '${u.name}: online', '${state.online}');

      final t = state.targetTemperature;
      _add(t >= kMinTemp && t <= kMaxTemp ? _Level.ok : _Level.warn, '${u.name}: target',
          '$t° (expected $kMinTemp–$kMaxTemp)');

      _add(state.indoorTemperature != null ? _Level.ok : _Level.warn, '${u.name}: indoor sensor',
          state.indoorTemperature != null ? '${state.indoorTemperature}°' : 'no reading');

      _add(kModes.contains(state.operationalMode) ? _Level.ok : _Level.warn, '${u.name}: mode',
          state.operationalMode);
      _add(kSwingModes.contains(state.swingMode) ? _Level.ok : _Level.warn, '${u.name}: swing',
          state.swingMode);

      // latency: 5 samples
      final samples = <int>[];
      for (var i = 0; i < 5; i++) {
        try {
          final sw = Stopwatch()..start();
          await _api.getState(u.id);
          sw.stop();
          samples.add(sw.elapsedMilliseconds);
        } catch (_) {}
      }
      if (samples.isNotEmpty) {
        final avg = samples.reduce((a, b) => a + b) ~/ samples.length;
        _add(avg < 800 ? _Level.ok : _Level.warn, '${u.name}: latency',
            'avg $avg ms over ${samples.length} calls');
      } else {
        _add(_Level.fail, '${u.name}: latency', 'no samples succeeded');
      }
    }

    final fails = _results.where((r) => r.level == _Level.fail).length;
    final warns = _results.where((r) => r.level == _Level.warn).length;
    _add(
      fails > 0 ? _Level.fail : (warns > 0 ? _Level.warn : _Level.ok),
      'Summary',
      fails > 0 ? '$fails problem(s), $warns warning(s)' : (warns > 0 ? '$warns warning(s)' : 'all checks passed'),
    );
    if (mounted) setState(() => _running = false);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    Color colorFor(_Level l) => switch (l) {
          _Level.ok => Colors.green,
          _Level.warn => Colors.orange,
          _Level.fail => scheme.error,
          _Level.info => scheme.onSurfaceVariant,
        };
    IconData iconFor(_Level l) => switch (l) {
          _Level.ok => Icons.check_circle,
          _Level.warn => Icons.warning_amber,
          _Level.fail => Icons.error,
          _Level.info => Icons.info_outline,
        };

    return Scaffold(
      appBar: AppBar(title: const Text('Diagnostics')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: FilledButton.icon(
              onPressed: _running ? null : _run,
              icon: _running
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.play_arrow),
              label: Text(_running ? 'Running…' : 'Run diagnosis'),
              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
            ),
          ),
          Expanded(
            child: _results.isEmpty
                ? Center(
                    child: Text('Tap “Run diagnosis” to test the connection and every unit.',
                        style: TextStyle(color: scheme.onSurfaceVariant)))
                : ListView.separated(
                    itemCount: _results.length,
                    separatorBuilder: (_, _) => const Divider(height: 1),
                    itemBuilder: (context, i) {
                      final r = _results[i];
                      return ListTile(
                        leading: Icon(iconFor(r.level), color: colorFor(r.level)),
                        title: Text(r.label),
                        subtitle: Text(r.detail),
                        dense: true,
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
