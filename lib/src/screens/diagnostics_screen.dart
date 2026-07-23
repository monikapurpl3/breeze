import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../api_client.dart';
import '../app_scope.dart';
import '../models.dart';

enum _Level { ok, warn, fail, info }

/// One line of the report. A [section] check is a header (no icon, no
/// pass/fail weight); everything else is a real check that counts toward the
/// summary.
class _Check {
  final _Level level;
  final String label;
  final String detail;
  final bool isSection;
  _Check(this.level, this.label, this.detail) : isSection = false;
  _Check.section(this.label)
      : level = _Level.info,
        detail = '',
        isSection = true;
}

/// In-app diagnostics — the phone-side mirror of `breeze-core diag`. Where the
/// CLI can read config.json and inspect the host's service manager, the app
/// can't; everything else in the battery is reproduced from what an
/// authenticated client can observe over HTTP: build/features, auth posture,
/// this device's own credential, secret sanitisation, input validation, batch
/// state, the live stream, per-unit health + capabilities, and the scheduler.
class DiagnosticsScreen extends StatefulWidget {
  const DiagnosticsScreen({super.key});
  @override
  State<DiagnosticsScreen> createState() => _DiagnosticsScreenState();
}

class _DiagnosticsScreenState extends State<DiagnosticsScreen> {
  final List<_Check> _results = [];
  bool _running = false;
  Set<String> _features = const {};

  ApiClient get _api => AppScope.of(context).api!;

  void _add(_Level l, String label, String detail) {
    if (mounted) setState(() => _results.add(_Check(l, label, detail)));
  }

  void _section(String title) {
    if (mounted) setState(() => _results.add(_Check.section(title)));
  }

  Future<void> _run() async {
    setState(() {
      _running = true;
      _results.clear();
      _features = const {};
    });

    List<UnitSummary> units = [];
    try {
      units = await _connectivity();
    } on ApiException catch (e) {
      _add(_Level.fail, 'Server unreachable', e.message);
      _finish();
      return;
    }

    await _authPosture();
    await _thisDevice();
    await _pairedDevices();
    await _configSanitisation();
    await _inputValidation(units);
    await _batchState(units);
    await _liveStream();
    for (final u in units) {
      await _diagnoseUnit(u);
    }
    await _programs();
    _summary();
    _finish();
  }

  void _finish() {
    if (mounted) setState(() => _running = false);
  }

  // -- connectivity + build ------------------------------------------------

  Future<List<UnitSummary>> _connectivity() async {
    _section('Connectivity & build');
    final sw = Stopwatch()..start();
    final units = await _api.listUnits(); // throws → caller reports unreachable
    sw.stop();
    _add(_Level.ok, 'Server reachable', '${units.length} unit(s) · ${sw.elapsedMilliseconds} ms');

    try {
      final h = await _api.health();
      _add(_Level.ok, 'Health endpoint', 'status=${h['status'] ?? '?'}');
    } on ApiException catch (e) {
      _add(e.status == 404 ? _Level.info : _Level.warn, 'Health endpoint',
          e.status == 404 ? 'not present (server < 2.4.0)' : e.message);
    }

    try {
      final info = await _api.serverInfo();
      _features = ((info['features'] as List?)?.cast<String>() ?? const <String>[]).toSet();
      final ver = info['version'] ?? '?';
      final commit = info['commit'] ?? 'unknown';
      _add(_Level.ok, 'Server version', 'Breeze Core $ver (commit $commit)');
      _add(_Level.info, 'Advertised features',
          _features.isEmpty ? 'none advertised' : (_features.toList()..sort()).join(', '));
      final serverUnits = (info['units'] as num?)?.toInt();
      if (serverUnits != null) {
        _add(serverUnits == units.length ? _Level.ok : _Level.warn, 'Unit-count parity',
            serverUnits == units.length
                ? 'server and listing agree ($serverUnits)'
                : 'server reports $serverUnits, listing has ${units.length}');
      }
    } on ApiException catch (e) {
      _add(_Level.warn, 'Server version', 'could not read /api/version — ${e.message}');
    }
    return units;
  }

  // -- authentication posture (security) -----------------------------------

  Future<void> _authPosture() async {
    _section('Authentication posture');
    // No key at all → must be rejected.
    final noKey = await _api.probe('GET', '/api/units', sendKey: false, sendToken: false);
    _add(noKey == 401 ? _Level.ok : _Level.fail, 'No key rejected',
        noKey == 401 ? 'correctly returns 401' : 'returned $noKey, expected 401');

    // Wrong key → must be rejected.
    final wrong = await _api.probe('GET', '/api/units',
        keyOverride: 'definitely-not-the-real-key', sendToken: false);
    _add(wrong == 401 ? _Level.ok : _Level.fail, 'Wrong key rejected',
        wrong == 401 ? 'correctly returns 401' : 'returned $wrong, expected 401');

    // Correct key but no device credential → is the control API token-gated?
    final keyOnly = await _api.probe('GET', '/api/units', sendToken: false);
    if (keyOnly == 401) {
      _add(_Level.ok, 'Control API is token-gated',
          'key alone is refused (401) — a device credential is also required (hardened)');
    } else if (keyOnly == 200) {
      _add(_Level.warn, 'Control API not token-gated',
          'key alone is accepted (200) — older or loosened build');
    } else {
      _add(_Level.warn, 'Token-gating', 'key alone returned $keyOnly (expected 200 or 401)');
    }
  }

  // -- this device's own credential ----------------------------------------

  Future<void> _thisDevice() async {
    _section('This device');
    final v = _api.authVersion;
    _add(v >= 2 ? _Level.ok : _Level.warn, 'Auth profile',
        v >= 2
            ? 'v2 — requests signed with a per-device Ed25519 key'
            : 'v1 — legacy bearer token (upgrades to v2 automatically when the server supports it)');

    try {
      final me = await _api.whoami();
      final label = me['label'] ?? '?';
      final av = (me['auth_version'] as num?)?.toInt() ?? v;
      _add(_Level.ok, 'Server recognises this device', 'label "$label" · auth v$av');

      final exp = me['expires_at'];
      final now = DateTime.now().millisecondsSinceEpoch / 1000.0;
      if (exp == null) {
        _add(_Level.info, 'Credential expiry', 'no expiry set');
      } else if (exp is num) {
        final when = DateTime.fromMillisecondsSinceEpoch((exp * 1000).round());
        final ymd = '${when.year}-${_pad2(when.month)}-${_pad2(when.day)}';
        if (exp < now) {
          _add(_Level.fail, 'Credential expired', 're-pair this device (expired $ymd)');
        } else if (exp < now + 7 * 86400) {
          _add(_Level.warn, 'Credential expires soon', 'within 7 days (on $ymd)');
        } else {
          _add(_Level.ok, 'Credential valid', 'expires $ymd');
        }
      }
    } on ApiException catch (e) {
      _add(e.status == 404 ? _Level.info : _Level.warn, 'whoami',
          e.status == 404 ? 'server predates 3.0 (no /whoami) — skipping' : e.message);
    }
  }

  // -- paired devices (admin, LAN-gated) -----------------------------------

  Future<void> _pairedDevices() async {
    _section('Paired devices');
    try {
      final devices = await _api.listDevices();
      _add(_Level.ok, 'Enrolled devices', '${devices.length} token(s)');
      final now = DateTime.now().millisecondsSinceEpoch / 1000.0;
      for (final d in devices.whereType<Map>()) {
        final label = d['label'] ?? '?';
        final exp = d['expires_at'];
        if (exp is num && exp < now) {
          _add(_Level.warn, '  $label', 'token expired — revoke it');
        } else if (exp is num && exp < now + 7 * 86400) {
          _add(_Level.warn, '  $label', 'expires within 7 days');
        }
      }
    } on ApiException catch (e) {
      if (e.status == 401 || e.status == 403) {
        _add(_Level.info, 'Device management', 'needs the key from the LAN — skipping (off-LAN?)');
      } else if (e.status == 404) {
        _add(_Level.info, 'Device management', 'endpoint not present — skipping');
      } else {
        _add(_Level.warn, 'Device management', e.message);
      }
    }
  }

  // -- config secret sanitisation ------------------------------------------

  Future<void> _configSanitisation() async {
    if (_features.isNotEmpty && !_features.contains('config_api')) return;
    _section('Config API (secret sanitisation)');
    try {
      final body = await _api.fetchConfig();
      final n = _leaks(body);
      _add(n == 0 ? _Level.ok : _Level.fail, 'No secrets exposed',
          n == 0 ? 'config response is sanitised' : '$n secret-looking value(s) exposed — possible leak');
      final appearsVerbatim = jsonEncode(body).contains(_api.apiKey);
      _add(appearsVerbatim ? _Level.fail : _Level.ok, 'API key not echoed',
          appearsVerbatim ? 'the API key appears verbatim in /api/config — leak' : 'the API key is absent from the response');
    } on ApiException catch (e) {
      if (e.status == 404) {
        _add(_Level.info, 'Config API', 'not present (server < 2.2.0) — skipping');
      } else if (e.status == 401 || e.status == 403) {
        _add(_Level.info, 'Config API', 'needs key+token from the LAN — skipping');
      } else {
        _add(_Level.warn, 'Config API', e.message);
      }
    }
  }

  int _leaks(Object? obj) {
    var n = 0;
    if (obj is Map) {
      obj.forEach((k, v) {
        final kl = k.toString().toLowerCase();
        final secretish = kl.contains('api_key') || kl.contains('token') || kl == 'key' || kl.endsWith('_key');
        if (secretish && v != null && v != false && v != '') n++;
        n += _leaks(v);
      });
    } else if (obj is List) {
      for (final x in obj) {
        n += _leaks(x);
      }
    }
    return n;
  }

  // -- input validation ----------------------------------------------------

  Future<void> _inputValidation(List<UnitSummary> units) async {
    _section('Input validation');
    final unknown = await _api.probe('GET', '/api/units/nonexistent-unit-id/state');
    _add(unknown == 404 ? _Level.ok : _Level.warn, 'Unknown unit → 404',
        unknown == 404 ? 'correctly returns 404' : 'returned $unknown (expected 404)');

    if (units.isEmpty) {
      _add(_Level.info, 'Bounds check', 'no units to test against');
      return;
    }
    // An out-of-range target is rejected before the unit is ever touched, so
    // this is a safe probe — it never changes how a unit is running.
    final bad = await _api.probe('POST', '/api/units/${units.first.id}/control',
        body: {'target_temperature': 99});
    if (bad == 422 || bad == 400) {
      _add(_Level.ok, 'Out-of-range rejected', 'target_temperature=99 refused with $bad');
    } else if (bad >= 200 && bad < 300) {
      _add(_Level.fail, 'Out-of-range ACCEPTED', 'server took target_temperature=99 ($bad) — bounds not enforced');
    } else {
      _add(_Level.warn, 'Bounds check', 'out-of-range control returned $bad (expected 422)');
    }
  }

  // -- batch state ---------------------------------------------------------

  Future<void> _batchState(List<UnitSummary> units) async {
    if (_features.isNotEmpty && !_features.contains('batch_state')) return;
    _section('Batch state');
    try {
      final sw = Stopwatch()..start();
      final b = await _api.listStates();
      sw.stop();
      _add(_Level.ok, 'One-shot batch', '${b.states.length} state(s) in ${sw.elapsedMilliseconds} ms');
      if (b.errors.isNotEmpty) {
        _add(_Level.warn, 'Unreachable in batch',
            '${b.errors.length} unit(s): ${b.errors.map((e) => e['name'] ?? e['id']).join(', ')}');
      }
      final seen = b.states.length + b.errors.length;
      _add(seen == units.length ? _Level.ok : _Level.warn, 'Batch coverage',
          seen == units.length ? 'covers all ${units.length} unit(s)' : 'covered $seen of ${units.length}');
    } on ApiException catch (e) {
      _add(e.status == 404 ? _Level.info : _Level.warn, 'Batch state',
          e.status == 404 ? 'not present (server < 2.4.0) — skipping' : e.message);
    }
  }

  // -- live stream (SSE) ---------------------------------------------------

  Future<void> _liveStream() async {
    _section('Live stream (SSE)');
    if (_features.isNotEmpty && !_features.contains('live_stream')) {
      _add(_Level.info, 'Live updates', 'server doesn’t advertise live_stream — skipping');
      return;
    }
    try {
      final first = await _api.streamStates().first.timeout(const Duration(seconds: 6));
      _add(_Level.ok, 'Stream connected', 'first live update received (${first.name})');
    } on TimeoutException {
      _add(_Level.warn, 'Stream connected', 'no update pushed within 6 s (idle is normal)');
    } on ApiException catch (e) {
      _add(e.status == 404 ? _Level.info : _Level.warn, 'Live stream',
          e.status == 404 ? 'endpoint not present — skipping' : e.message);
    } catch (e) {
      _add(_Level.warn, 'Live stream', 'closed without an update ($e)');
    }
  }

  // -- per unit ------------------------------------------------------------

  Future<void> _diagnoseUnit(UnitSummary u) async {
    _section('Unit: ${u.name}');
    UnitState state;
    try {
      final sw = Stopwatch()..start();
      state = await _api.getState(u.id);
      sw.stop();
      _add(_Level.ok, 'State fetched', '${sw.elapsedMilliseconds} ms');
    } on ApiException catch (e) {
      _add(_Level.fail, 'State', e.message);
      return;
    }

    _add(state.online ? _Level.ok : _Level.warn, 'Online', '${state.online}');
    final t = state.targetTemperature;
    _add(t >= kMinTemp && t <= kMaxTemp ? _Level.ok : _Level.warn, 'Target',
        '$t° (expected $kMinTemp–$kMaxTemp)');
    _add(state.indoorTemperature != null ? _Level.ok : _Level.warn, 'Indoor sensor',
        state.indoorTemperature != null ? '${state.indoorTemperature}°' : 'no reading');
    _add(_Level.info, 'Readouts',
        'power=${state.powerState} outdoor=${state.outdoorTemperature ?? '—'}° '
        'fan=${state.fanSpeed} eco=${state.eco} turbo=${state.turbo}');
    _add(kModes.contains(state.operationalMode) ? _Level.ok : _Level.warn, 'Mode',
        state.operationalMode);
    _add(kSwingModes.contains(state.swingMode) ? _Level.ok : _Level.warn, 'Swing',
        state.swingMode);

    // capabilities (Breeze Core >= 3.0.0) — what the hardware actually offers
    try {
      final caps = await _api.capabilities(u.id);
      final modes = (caps['operational_modes'] as List?)?.length;
      final range = '${caps['min_target_temperature']}–${caps['max_target_temperature']}°';
      final extras = <String>[
        if (caps['supports_eco'] == true) 'eco',
        if (caps['supports_turbo'] == true) 'turbo',
        if (caps['supports_horizontal_swing'] == true) 'h-swing',
      ];
      _add(_Level.ok, 'Capabilities',
          '${modes ?? '?'} mode(s), range $range${extras.isEmpty ? '' : ', ${extras.join('/')}'}');
    } on ApiException catch (e) {
      _add(e.status == 404 ? _Level.info : _Level.warn, 'Capabilities',
          e.status == 404 ? 'endpoint not present — skipping' : e.message);
    }

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
      _add(avg < 800 ? _Level.ok : _Level.warn, 'Latency',
          'avg $avg ms over ${samples.length} calls${avg >= 800 ? ' — check Wi-Fi to this unit' : ''}');
    } else {
      _add(_Level.fail, 'Latency', 'no samples succeeded');
    }
  }

  // -- programs / scheduler ------------------------------------------------

  Future<void> _programs() async {
    if (_features.isNotEmpty && !_features.contains('programs')) return;
    _section('Programs / scheduler');
    try {
      final st = await _api.schedulerStatus();
      final running = st['running'] == true;
      _add(running ? _Level.ok : _Level.warn, 'Scheduler',
          'running=${st['running']} · runs=${st['runs']} · last=${st['last_run'] ?? '—'}');
    } on ApiException catch (e) {
      _add(e.status == 404 ? _Level.info : _Level.warn, 'Scheduler',
          e.status == 404 ? 'programs feature not present — skipping' : e.message);
      return;
    }
    try {
      final programs = await _api.listPrograms();
      final kinds = <String, int>{'favourite': 0, 'schedule': 0, 'curve': 0};
      for (final p in programs) {
        kinds[p.kind] = (kinds[p.kind] ?? 0) + 1;
      }
      final enabled = programs.where((p) => p.enabled).length;
      _add(_Level.ok, 'Programs',
          '${programs.length}: ${kinds['favourite']} favourite, ${kinds['schedule']} schedule, '
          '${kinds['curve']} curve ($enabled enabled)');
    } on ApiException catch (_) {/* status already reported */}
  }

  void _summary() {
    _section('Summary');
    final fails = _results.where((r) => !r.isSection && r.level == _Level.fail).length;
    final warns = _results.where((r) => !r.isSection && r.level == _Level.warn).length;
    _add(
      fails > 0 ? _Level.fail : (warns > 0 ? _Level.warn : _Level.ok),
      fails > 0 ? 'Problems found' : (warns > 0 ? 'Passed with warnings' : 'All checks passed'),
      fails > 0 ? '$fails problem(s), $warns warning(s)' : (warns > 0 ? '$warns warning(s)' : 'no issues'),
    );
    HapticFeedback.mediumImpact();
  }

  static String _pad2(int n) => n.toString().padLeft(2, '0');

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
              label: Text(_running ? 'Running…' : 'Run full diagnosis'),
              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
            ),
          ),
          Expanded(
            child: _results.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 32),
                      child: Text(
                        'Tap “Run full diagnosis” to check connectivity, the server build, '
                        'authentication and security posture, this device’s credential, '
                        'input validation, the live stream, and every unit.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: scheme.onSurfaceVariant),
                      ),
                    ),
                  )
                : ListView.builder(
                    itemCount: _results.length,
                    itemBuilder: (context, i) {
                      final r = _results[i];
                      if (r.isSection) {
                        return Padding(
                          padding: const EdgeInsets.fromLTRB(16, 20, 16, 6),
                          child: Text(
                            r.label.toUpperCase(),
                            style: TextStyle(
                              color: scheme.primary,
                              fontWeight: FontWeight.w700,
                              fontSize: 12,
                              letterSpacing: 0.8,
                            ),
                          ),
                        );
                      }
                      return ListTile(
                        leading: Icon(iconFor(r.level), color: colorFor(r.level)),
                        title: Text(r.label),
                        subtitle: r.detail.isEmpty ? null : Text(r.detail),
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
