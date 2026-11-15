import 'dart:async';
import 'dart:convert';

import 'package:material_ui/material_ui.dart';

import '../haptics.dart';
import '../app_info.dart';
import '../api_client.dart';
import '../app_scope.dart';
import '../l10n.dart';
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

  /// The messages for the run in progress, taken when it starts: the checks
  /// go on across many awaits, where the context is better left alone.
  late AppLocalizations _l;

  ApiClient get _api => AppScope.of(context).api!;

  /// True when the configured server is a private/loopback address, i.e. we're
  /// on the same LAN. Used to keep LAN-only admin probes off the wire when
  /// we're remote (a 403 there can get the client's IP banned).
  bool get _serverIsPrivate {
    final host = Uri.tryParse(_api.baseUrl)?.host ?? '';
    if (host == 'localhost') return true;
    final m = RegExp(r'^(\d+)\.(\d+)\.\d+\.\d+$').firstMatch(host);
    if (m == null) return false;
    final a = int.parse(m.group(1)!), b = int.parse(m.group(2)!);
    return a == 10 ||
        a == 127 ||
        (a == 192 && b == 168) ||
        (a == 172 && b >= 16 && b <= 31);
  }

  void _add(_Level l, String label, String detail) {
    if (mounted) setState(() => _results.add(_Check(l, label, detail)));
  }

  void _section(String title) {
    if (mounted) setState(() => _results.add(_Check.section(title)));
  }

  Future<void> _run() async {
    _l = context.l10n;
    setState(() {
      _running = true;
      _results.clear();
      _features = const {};
    });

    List<UnitSummary> units = [];
    try {
      units = await _connectivity();
    } on ApiException catch (e) {
      _add(_Level.fail, _l.diagServerUnreachable, e.message);
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
    _section(_l.diagSectionConnectivity);
    final sw = Stopwatch()..start();
    final units = await _api.listUnits(); // throws → caller reports unreachable
    sw.stop();
    _add(_Level.ok, _l.diagServerReachable, _l.diagServerReachableDetail(units.length, sw.elapsedMilliseconds));

    try {
      final h = await _api.health();
      _add(_Level.ok, _l.diagHealthEndpoint, 'status=${h['status'] ?? '?'}');
    } on ApiException catch (e) {
      _add(e.status == 404 ? _Level.info : _Level.warn, _l.diagHealthEndpoint,
          e.status == 404 ? _l.diagNotPresentServer('2.4.0') : e.message);
    }

    try {
      final info = await _api.serverInfo();
      _features = ((info['features'] as List?)?.cast<String>() ?? const <String>[]).toSet();
      final ver = info['version'] ?? '?';
      final commit = info['commit'] ?? _l.diagUnknown;
      _add(_Level.ok, _l.diagServerVersion, _l.diagServerVersionDetail('$ver', '$commit'));
      _add(_Level.info, _l.diagAppVersion, 'Breeze ${AppInfo.version}');
      _add(_Level.info, _l.diagFeatures,
          _features.isEmpty ? _l.diagFeaturesNone : (_features.toList()..sort()).join(', '));
      final serverUnits = (info['units'] as num?)?.toInt();
      if (serverUnits != null) {
        _add(serverUnits == units.length ? _Level.ok : _Level.warn, _l.diagUnitParity,
            serverUnits == units.length
                ? _l.diagUnitParityAgree(serverUnits)
                : _l.diagUnitParityDiffer(serverUnits, units.length));
      }
    } on ApiException catch (e) {
      _add(_Level.warn, _l.diagServerVersion, _l.diagVersionUnreadable(e.message));
    }
    return units;
  }

  // -- authentication posture (security) -----------------------------------

  Future<void> _authPosture() async {
    _section(_l.diagSectionAuth);
    // No key at all → must be rejected.
    final noKey = await _api.probe('GET', '/api/units', sendKey: false, sendToken: false);
    _add(noKey == 401 ? _Level.ok : _Level.fail, _l.diagNoKeyRejected,
        noKey == 401 ? _l.diagCorrectlyReturns(401) : _l.diagReturnedExpected(noKey, 401));

    // Wrong key → must be rejected.
    final wrong = await _api.probe('GET', '/api/units',
        keyOverride: 'definitely-not-the-real-key', sendToken: false);
    _add(wrong == 401 ? _Level.ok : _Level.fail, _l.diagWrongKeyRejected,
        wrong == 401 ? _l.diagCorrectlyReturns(401) : _l.diagReturnedExpected(wrong, 401));

    // Correct key but no device credential → is the control API token-gated?
    final keyOnly = await _api.probe('GET', '/api/units', sendToken: false);
    if (keyOnly == 401) {
      _add(_Level.ok, _l.diagTokenGated, _l.diagTokenGatedDetail(401));
    } else if (keyOnly == 200) {
      _add(_Level.warn, _l.diagNotTokenGated, _l.diagNotTokenGatedDetail(200));
    } else {
      _add(_Level.warn, _l.diagTokenGating, _l.diagTokenGatingDetail(keyOnly, 200, 401));
    }
  }

  // -- this device's own credential ----------------------------------------

  Future<void> _thisDevice() async {
    _section(_l.diagSectionThisDevice);
    // Device clock vs server clock. A drift past the server's window rejects
    // every signed request — the exact failure that looked like "the app lost
    // my login". The client corrects itself, but say so out loud.
    final skew = _api.clockOffsetSeconds;
    if (skew == 0) {
      _add(_Level.ok, _l.diagDeviceClock, _l.diagClockInSync);
    } else {
      _add(_Level.warn, _l.diagDeviceClock,
          skew > 0 ? _l.diagClockBehind(skew.abs()) : _l.diagClockAhead(skew.abs()));
    }

    final v = _api.authVersion;
    _add(v >= 2 ? _Level.ok : _Level.warn, _l.diagAuthProfile,
        v >= 2 ? _l.diagAuthV2 : _l.diagAuthV1);

    try {
      final me = await _api.whoami();
      final label = me['label'] ?? '?';
      final av = (me['auth_version'] as num?)?.toInt() ?? v;
      _add(_Level.ok, _l.diagRecognised, _l.diagRecognisedDetail('$label', av));

      final exp = me['expires_at'];
      final now = DateTime.now().millisecondsSinceEpoch / 1000.0;
      if (exp == null) {
        _add(_Level.info, _l.diagCredentialExpiry, _l.diagNoExpiry);
      } else if (exp is num) {
        final when = DateTime.fromMillisecondsSinceEpoch((exp * 1000).round());
        final ymd = '${when.year}-${_pad2(when.month)}-${_pad2(when.day)}';
        if (exp < now) {
          _add(_Level.fail, _l.diagCredentialExpired, _l.diagCredentialExpiredDetail(ymd));
        } else if (exp < now + 7 * 86400) {
          _add(_Level.warn, _l.diagCredentialExpiresSoon, _l.diagCredentialExpiresSoonDetail(ymd));
        } else {
          _add(_Level.ok, _l.diagCredentialValid, _l.diagCredentialValidDetail(ymd));
        }
      }
    } on ApiException catch (e) {
      _add(e.status == 404 ? _Level.info : _Level.warn, 'whoami',
          e.status == 404 ? _l.diagWhoamiMissing('3.0') : e.message);
    }
  }

  // -- paired devices (admin, LAN-gated) -----------------------------------

  Future<void> _pairedDevices() async {
    _section(_l.diagSectionPairedDevices);
    // `/api/auth/devices` is admin + LAN-only, so off-LAN it returns 403 — and
    // a server behind a fail2ban tripwire may treat a single 403 on an admin
    // endpoint as an intrusion attempt and ban the client's IP (which, behind
    // NAT, is shared with everyone else in the house). Never probe it unless
    // we're plainly talking to a private address.
    if (!_serverIsPrivate) {
      _add(_Level.info, _l.diagDeviceManagement, _l.diagDeviceManagementSkipped);
      return;
    }
    try {
      final devices = await _api.listDevices();
      _add(_Level.ok, _l.diagEnrolledDevices, _l.diagTokenCount(devices.length));
      final now = DateTime.now().millisecondsSinceEpoch / 1000.0;
      for (final d in devices.whereType<Map>()) {
        final label = d['label'] ?? '?';
        final exp = d['expires_at'];
        if (exp is num && exp < now) {
          _add(_Level.warn, '  $label', _l.diagTokenExpired);
        } else if (exp is num && exp < now + 7 * 86400) {
          _add(_Level.warn, '  $label', _l.diagTokenExpiresSoon);
        }
      }
    } on ApiException catch (e) {
      if (e.status == 401 || e.status == 403) {
        _add(_Level.info, _l.diagDeviceManagement, _l.diagNeedsLanKey);
      } else if (e.status == 404) {
        _add(_Level.info, _l.diagDeviceManagement, _l.diagEndpointMissing);
      } else {
        _add(_Level.warn, _l.diagDeviceManagement, e.message);
      }
    }
  }

  // -- config secret sanitisation ------------------------------------------

  Future<void> _configSanitisation() async {
    if (_features.isNotEmpty && !_features.contains('config_api')) return;
    _section(_l.diagSectionConfig);
    try {
      final body = await _api.fetchConfig();
      final n = _leaks(body);
      _add(n == 0 ? _Level.ok : _Level.fail, _l.diagNoSecrets,
          n == 0 ? _l.diagConfigSanitised : _l.diagSecretsExposed(n));
      final appearsVerbatim = jsonEncode(body).contains(_api.apiKey);
      _add(appearsVerbatim ? _Level.fail : _Level.ok, _l.diagKeyNotEchoed,
          appearsVerbatim ? _l.diagKeyEchoed : _l.diagKeyAbsent);
    } on ApiException catch (e) {
      if (e.status == 404) {
        _add(_Level.info, _l.diagConfigApi, _l.diagNotPresentServerSkipping('2.2.0'));
      } else if (e.status == 401 || e.status == 403) {
        _add(_Level.info, _l.diagConfigApi, _l.diagNeedsLanKeyToken);
      } else {
        _add(_Level.warn, _l.diagConfigApi, e.message);
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
    _section(_l.diagSectionInput);
    final unknown = await _api.probe('GET', '/api/units/nonexistent-unit-id/state');
    _add(unknown == 404 ? _Level.ok : _Level.warn, _l.diagUnknownUnit(404),
        unknown == 404 ? _l.diagCorrectlyReturns(404) : _l.diagReturnedExpectedParen(unknown, 404));

    if (units.isEmpty) {
      _add(_Level.info, _l.diagBoundsCheck, _l.diagNoUnitsToTest);
      return;
    }
    // An out-of-range target is rejected before the unit is ever touched, so
    // this is a safe probe — it never changes how a unit is running.
    final bad = await _api.probe('POST', '/api/units/${units.first.id}/control',
        body: {'target_temperature': 99});
    if (bad == 422 || bad == 400) {
      _add(_Level.ok, _l.diagOutOfRangeRejected, _l.diagOutOfRangeRejectedDetail('target_temperature=99', bad));
    } else if (bad >= 200 && bad < 300) {
      _add(_Level.fail, _l.diagOutOfRangeAccepted, _l.diagOutOfRangeAcceptedDetail('target_temperature=99', bad));
    } else {
      _add(_Level.warn, _l.diagBoundsCheck, _l.diagOutOfRangeOther(bad, 422));
    }
  }

  // -- batch state ---------------------------------------------------------

  Future<void> _batchState(List<UnitSummary> units) async {
    if (_features.isNotEmpty && !_features.contains('batch_state')) return;
    _section(_l.diagBatchState);
    try {
      final sw = Stopwatch()..start();
      final b = await _api.listStates();
      sw.stop();
      _add(_Level.ok, _l.diagOneShotBatch, _l.diagBatchDetail(b.states.length, sw.elapsedMilliseconds));
      if (b.errors.isNotEmpty) {
        _add(_Level.warn, _l.diagUnreachableInBatch,
            _l.diagUnreachableDetail(b.errors.length, b.errors.map((e) => e['name'] ?? e['id']).join(', ')));
      }
      final seen = b.states.length + b.errors.length;
      _add(seen == units.length ? _Level.ok : _Level.warn, _l.diagBatchCoverage,
          seen == units.length ? _l.diagCoversAll(units.length) : _l.diagCoveredOf(seen, units.length));
    } on ApiException catch (e) {
      _add(e.status == 404 ? _Level.info : _Level.warn, _l.diagBatchState,
          e.status == 404 ? _l.diagNotPresentServerSkipping('2.4.0') : e.message);
    }
  }

  // -- live stream (SSE) ---------------------------------------------------

  Future<void> _liveStream() async {
    _section(_l.diagSectionLive);
    if (_features.isNotEmpty && !_features.contains('live_stream')) {
      _add(_Level.info, _l.diagLiveUpdates, _l.diagNoLiveStreamFeature('live_stream'));
      return;
    }
    try {
      final first = await _api.streamStates().first.timeout(const Duration(seconds: 6));
      _add(_Level.ok, _l.diagStreamConnected, _l.diagFirstUpdate(first.name));
    } on TimeoutException {
      _add(_Level.warn, _l.diagStreamConnected, _l.diagNoUpdateWithin(6));
    } on ApiException catch (e) {
      _add(e.status == 404 ? _Level.info : _Level.warn, _l.diagLiveStream,
          e.status == 404 ? _l.diagEndpointMissing : e.message);
    } catch (e) {
      _add(_Level.warn, _l.diagLiveStream, _l.diagStreamClosed('$e'));
    }
  }

  // -- per unit ------------------------------------------------------------

  Future<void> _diagnoseUnit(UnitSummary u) async {
    _section(_l.diagSectionUnit(u.name));
    UnitState state;
    try {
      final sw = Stopwatch()..start();
      state = await _api.getState(u.id);
      sw.stop();
      _add(_Level.ok, _l.diagStateFetched, '${sw.elapsedMilliseconds} ms');
    } on ApiException catch (e) {
      _add(_Level.fail, _l.diagState, e.message);
      return;
    }

    _add(state.online ? _Level.ok : _Level.warn, _l.diagOnline, '${state.online}');
    final t = state.targetTemperature;
    _add(t >= kMinTemp && t <= kMaxTemp ? _Level.ok : _Level.warn, _l.diagTarget,
        _l.diagTargetDetail(_dec(t), _dec(kMinTemp), _dec(kMaxTemp)));
    _add(state.indoorTemperature != null ? _Level.ok : _Level.warn, _l.diagIndoorSensor,
        state.indoorTemperature != null ? '${_dec(state.indoorTemperature)}°' : _l.diagNoReading);
    _add(_Level.info, _l.diagReadouts,
        'power=${state.powerState} outdoor=${state.outdoorTemperature ?? '—'}° '
        'fan=${state.fanSpeed} eco=${state.eco} turbo=${state.turbo}');
    _add(kModes.contains(state.operationalMode) ? _Level.ok : _Level.warn, _l.labelMode,
        state.operationalMode);
    _add(kSwingModes.contains(state.swingMode) ? _Level.ok : _Level.warn, _l.diagSwing,
        state.swingMode);

    // capabilities (Breeze Core >= 3.0.0) — what the hardware actually offers
    try {
      final caps = await _api.capabilities(u.id);
      final modes = (caps['operational_modes'] as List?)?.length;
      final range = '${_dec(caps['min_target_temperature'])}–${_dec(caps['max_target_temperature'])}°';
      final extras = <String>[
        if (caps['supports_eco'] == true) 'eco',
        if (caps['supports_turbo'] == true) 'turbo',
        if (caps['supports_horizontal_swing'] == true) 'h-swing',
      ];
      final modeCount = modes == null ? _l.diagModeCountUnknown : _l.diagModeCount(modes);
      _add(_Level.ok, _l.diagCapabilities,
          extras.isEmpty
              ? _l.diagCapabilitiesDetail(modeCount, range)
              : _l.diagCapabilitiesDetailExtras(modeCount, range, extras.join('/')));
    } on ApiException catch (e) {
      _add(e.status == 404 ? _Level.info : _Level.warn, _l.diagCapabilities,
          e.status == 404 ? _l.diagEndpointMissing : e.message);
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
      _add(avg < 800 ? _Level.ok : _Level.warn, _l.diagLatency,
          avg >= 800 ? _l.diagLatencySlow(avg, samples.length) : _l.diagLatencyDetail(avg, samples.length));
    } else {
      _add(_Level.fail, _l.diagLatency, _l.diagNoSamples);
    }
  }

  // -- programs / scheduler ------------------------------------------------

  Future<void> _programs() async {
    if (_features.isNotEmpty && !_features.contains('programs')) return;
    _section(_l.diagSectionPrograms);
    try {
      final st = await _api.schedulerStatus();
      final running = st['running'] == true;
      _add(running ? _Level.ok : _Level.warn, _l.diagScheduler,
          'running=${st['running']} · runs=${st['runs']} · last=${st['last_run'] ?? '—'}');
    } on ApiException catch (e) {
      _add(e.status == 404 ? _Level.info : _Level.warn, _l.diagScheduler,
          e.status == 404 ? _l.diagProgramsMissing : e.message);
      return;
    }
    try {
      final programs = await _api.listPrograms();
      final kinds = <String, int>{'favourite': 0, 'schedule': 0, 'curve': 0};
      for (final p in programs) {
        kinds[p.kind] = (kinds[p.kind] ?? 0) + 1;
      }
      final enabled = programs.where((p) => p.enabled).length;
      _add(_Level.ok, _l.diagPrograms,
          _l.diagProgramsDetail(programs.length, kinds['favourite']!, kinds['schedule']!,
              kinds['curve']!, enabled));
    } on ApiException catch (_) {/* status already reported */}
  }

  void _summary() {
    _section(_l.diagSectionSummary);
    final fails = _results.where((r) => !r.isSection && r.level == _Level.fail).length;
    final warns = _results.where((r) => !r.isSection && r.level == _Level.warn).length;
    _add(
      fails > 0 ? _Level.fail : (warns > 0 ? _Level.warn : _Level.ok),
      fails > 0 ? _l.diagProblemsFound : (warns > 0 ? _l.diagPassedWithWarnings : _l.diagAllPassed),
      fails > 0
          ? _l.diagProblemsAndWarnings(_l.diagProblemCount(fails), _l.diagWarningCount(warns))
          : (warns > 0 ? _l.diagWarningCount(warns) : _l.diagNoIssues),
    );
    if (fails > 0) {
      Haptics.failure();
    } else {
      Haptics.success();
    }
  }

  static String _pad2(int n) => n.toString().padLeft(2, '0');

  /// A reading as the server gave it, with the language's decimal separator.
  static String _dec(Object? v) => '$v'.replaceAll('.', decimalSeparator);

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
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
    // Said, not only drawn: "passed", "warning", "failed".
    String wordFor(_Level l) => switch (l) {
          _Level.ok => l10n.diagLevelPassed,
          _Level.warn => l10n.diagLevelWarning,
          _Level.fail => l10n.diagLevelFailed,
          _Level.info => l10n.diagLevelNote,
        };

    return Scaffold(
      appBar: AppBar(title: Text(l10n.diagTitle)),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: FilledButton.icon(
              onPressed: _running ? null : _run,
              icon: _running
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.play_arrow),
              label: Text(_running ? l10n.diagRunning : l10n.diagRun),
              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
            ),
          ),
          Expanded(
            child: _results.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 32),
                      child: Text(
                        l10n.diagIntro(l10n.diagRun),
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
                          child: Semantics(header: true, child: Text(
                            r.label.toUpperCase(),
                            // A heading, read in its own case (capitals can
                            // get spelled out letter by letter).
                            semanticsLabel: r.label,
                            style: TextStyle(
                              color: scheme.primary,
                              fontWeight: FontWeight.w700,
                              fontSize: 12,
                              letterSpacing: 0.8,
                            ),
                          )),
                        );
                      }
                      return ListTile(
                        leading: Icon(iconFor(r.level),
                            color: colorFor(r.level), semanticLabel: wordFor(r.level)),
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
