// The Nerd screen: everything knowable about this app, this phone's
// connection, and the server on the other end of it.
//
// Reached by tapping the version in Settings seven times, so it's deliberately
// out of the way — nothing here is needed to use the app, and all of it is
// useful exactly once, when something is wrong.
//
// It needs `GET /api/system`, which arrived in Breeze Core 3.0.5. Against an
// older server there is no partial version of this screen worth showing, so it
// says so plainly instead of rendering a page of blanks.

import 'dart:async';
import 'dart:convert';

import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';

import '../api_client.dart';
import '../app_info.dart';
import '../app_scope.dart';
import '../haptics.dart';
import '../l10n.dart';
import 'internal_tab.dart';

/// Server version this screen needs. Below it, the endpoint doesn't exist.
const _kMinServer = [3, 0, 5];

/// Compare a dotted version against [_kMinServer], ignoring any `-pre` suffix.
bool serverSupportsNerd(String? version) {
  if (version == null) return false;
  final core = version.split(RegExp(r'[-+]')).first;
  final parts = core.split('.').map((p) => int.tryParse(p) ?? 0).toList();
  for (var i = 0; i < _kMinServer.length; i++) {
    final v = i < parts.length ? parts[i] : 0;
    if (v != _kMinServer[i]) return v > _kMinServer[i];
  }
  return true;
}

class NerdScreen extends StatefulWidget {
  const NerdScreen({super.key});

  @override
  State<NerdScreen> createState() => _NerdScreenState();
}

class _NerdScreenState extends State<NerdScreen> {
  Map<String, dynamic>? _sys;
  String? _serverVersion;
  String Function(AppLocalizations l)? _error;
  bool _tooOld = false;
  bool _loading = true;
  int? _latencyMs;

  @override
  void initState() {
    super.initState();
    // After the first frame (which already shows the spinner): _load looks
    // AppScope up, and an inherited-widget lookup during initState asserts in
    // a debug build -- the error went into the unawaited future, and the tab
    // spun for ever there.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_load());
    });
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final api = AppScope.of(context).api;
    if (api == null) {
      setState(() {
        _loading = false;
        _error = (l) => l.nerdNotConnected;
      });
      return;
    }
    try {
      // Version first: it's cheap, unauthenticated beyond the key, and decides
      // whether the big call is even worth making.
      final info = await api.serverInfo();
      final version = info['version'] as String?;
      if (!serverSupportsNerd(version)) {
        setState(() {
          _loading = false;
          _tooOld = true;
          _serverVersion = version;
        });
        return;
      }
      // Time the real call — a round-trip number people can act on.
      final started = DateTime.now();
      final sys = await api.systemInfo();
      final ms = DateTime.now().difference(started).inMilliseconds;
      if (!mounted) return;
      setState(() {
        _sys = sys;
        _serverVersion = version;
        _latencyMs = ms;
        _loading = false;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      // A 404 from a server that claimed a new enough version still means the
      // endpoint isn't there; treat it the same as too-old rather than as an error.
      setState(() {
        _loading = false;
        if (e.status == 404) {
          _tooOld = true;
        } else {
          _error = (l) => l.nerdLoadFailed(e.message);
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = (l) => l.nerdLoadFailed(e.toString());
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    // Two tabs: what the app and server are (System), and the internal
    // settings that change how the app looks and connects (Internal). The
    // second works against any server, so it stays reachable when the first
    // can only say "womp womp".
    return DefaultTabController(
      length: 2,
      child: Builder(builder: (context) {
        final tabs = DefaultTabController.of(context);
        return ListenableBuilder(
          listenable: tabs,
          builder: (context, _) => Scaffold(
            appBar: AppBar(
              title: const Text('Nerd'),
              actions: [
                if (tabs.index == 0) ...[
                  IconButton(
                    tooltip: context.l10n.nerdCopyAll,
                    icon: const Icon(Icons.copy_all_outlined),
                    onPressed: _sys == null ? null : _copyAll,
                  ),
                  IconButton(
                    tooltip: context.l10n.nerdRefresh,
                    icon: const Icon(Icons.refresh),
                    onPressed: _loading ? null : _load,
                  ),
                ],
              ],
              bottom: TabBar(
                tabs: [
                  Tab(icon: const Icon(Icons.memory), text: context.l10n.nerdTabSystem),
                  Tab(icon: const Icon(Icons.tune), text: context.l10n.nerdTabInternal),
                ],
              ),
            ),
            body: TabBarView(
              children: [_body(), const InternalTab()],
            ),
          ),
        );
      }),
    );
  }

  Widget _body() {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_tooOld) return _WompWomp(version: _serverVersion);
    if (_error != null) return _Problem(message: _error!(context.l10n), onRetry: _load);
    final sys = _sys;
    if (sys == null) return const SizedBox.shrink();
    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 32),
      children: _sections(sys),
    );
  }

  // --- rendering ------------------------------------------------------------

  List<Widget> _sections(Map<String, dynamic> sys) {
    final server = _map(sys['server']);
    final os = _map(sys['os']);
    final init = _map(sys['init']);
    final cpu = _map(sys['cpu']);
    final net = _map(sys['network']);
    final conn = _map(sys['connection']);
    final settings = _map(sys['settings']);
    final storage = _map(sys['storage']);
    final scheduler = _map(sys['scheduler']);
    final programs = _map(sys['programs']);
    final python = _map(server['python']);
    final process = _map(sys['process']);
    final api = AppScope.of(context).api;
    final l = context.l10n;
    final authVersion = api?.authVersion ?? 1;

    return [
      _Section(l.nerdSectionApp, [
        _Row(l.nerdVersion, AppInfo.version),
        _Row(l.nerdPackage, AppInfo.packageName),
        _Row(l.nerdPlatform, '${AppInfo.os} · ${AppInfo.osVersion}'),
        _Row('Dart', AppInfo.dartVersion),
        if (AppInfo.sdks['dart'] != null) _Row(l.nerdDartSdkConstraint, AppInfo.sdks['dart']),
        if (AppInfo.sdks['flutter'] != null) _Row(l.nerdFlutterConstraint, AppInfo.sdks['flutter']),
      ]),
      _Section(l.nerdSectionConnection, [
        _Row(l.nerdServerUrl, api?.baseUrl),
        if (api != null && api.currentUrl.value != api.baseUrl)
          _Row(l.nerdAnsweringNow, l.nerdFallbackValue(api.currentUrl.value)),
        _Row(l.nerdLatency, _latencyMs == null ? null : l.nerdLatencyValue(_latencyMs!)),
        _Row(l.nerdAuthVersion, authVersion >= 2
            ? l.nerdAuthSigned(authVersion)
            : l.nerdAuthBearer(authVersion)),
        _Row(l.nerdSeenAs, conn['client_ip']?.toString()),
        _Row(l.nerdPrivateNetwork, _yesNo(conn['client_is_private'])),
        _Row(l.nerdReachedVia, conn['request_url']?.toString()),
        _Row(l.nerdHostHeader, conn['host_header']?.toString()),
        _Row(l.nerdScheme, conn['scheme']?.toString()),
        _Row(l.nerdHttpVersion, conn['http_version']?.toString()),
        _Row('X-Forwarded-For', conn['forwarded_for']?.toString()),
        _Row(l.nerdBehindProxy, _yesNo(conn['behind_proxy_enabled'])),
      ]),
      _Section(l.nerdSectionServer, [
        _Row(l.nerdVersion, '${server['name']} ${server['version']}'),
        _Row(l.nerdBuildCommit, server['commit']?.toString()),
        _Row(l.nerdUptime, _duration(server['uptime_seconds'])),
        _Row(l.nerdStarted, _when(server['started_at'])),
        _Row(l.nerdInstalled, _when(server['installed_at'])),
        _Row(l.nerdServerTime, _when(server['server_time'])),
        _Row(l.nerdTimeZone, '${server['timezone'] ?? '?'} '
            '(UTC${_offset(server['utc_offset_seconds'])})'),
        _Row(l.nerdProcessId, process['pid']?.toString()),
        _Row(l.nerdMemory, _bytes(process['rss_bytes'])),
      ]),
      _Section(l.nerdSectionHost, [
        _Row(l.nerdOs, os['pretty_name']?.toString()),
        _Row(l.nerdKernel, '${os['system'] ?? ''} ${os['kernel'] ?? ''}'.trim()),
        _Row(l.nerdKernelBuild, os['kernel_version']?.toString()),
        _Row(l.nerdInitSystem, init['detail'] == null
            ? init['name']?.toString()
            : '${init['name']} — ${init['detail']}'),
        _Row(l.nerdHostname, os['hostname']?.toString()),
        _Row(l.nerdArchitecture, cpu['arch']?.toString()),
        _Row('CPU', cpu['model']?.toString()),
        _Row(l.nerdCores, cpu['cores']?.toString()),
        _Row(l.nerdByteOrder, cpu['endianness']?.toString()),
        _Row('libc', os['libc']?.toString()),
        _Row(l.nerdMachineUptime, _duration(sys['machine_uptime_seconds'])),
        _Row(l.nerdLocalAddresses, _list(net['local_addresses'])),
      ]),
      _Section(l.nerdSectionServerComponents, [
        _Row('Python', '${python['version']} (${python['implementation']})'),
        _Row(l.nerdFrozenBundle, _yesNo(python['frozen'])),
        for (final e in _map(sys['components']).entries)
          _Row(e.key, e.value?.toString() ?? l.nerdNotInstalled),
      ]),
      _Section(l.nerdSectionAppComponents, [
        for (final e in (AppInfo.packages.entries.toList()
          ..sort((a, b) => a.key.compareTo(b.key))))
          _Row(e.key, e.value),
      ]),
      _Section(l.nerdSectionUnits, _units(sys['units'])),
      _Section(l.nerdSectionDevices, _devices(sys['devices'])),
      _Section(l.nerdSectionPrograms, [
        _Row(l.nerdPrograms, '${programs['total'] ?? 0} '
            '(${_byKind(programs['by_kind'])})'),
        _Row(l.nerdSchedulerRunning, _yesNo(scheduler['running'])),
        _Row(l.nerdTick, scheduler['tick_seconds'] == null
            ? null
            : '${scheduler['tick_seconds']} s'),
        _Row(l.nerdRuns, scheduler['runs']?.toString()),
        _Row(l.nerdErrors, scheduler['errors']?.toString()),
        _Row(l.nerdLastRun, scheduler['last_run']?.toString()),
      ]),
      _Section(l.nerdSectionSettings, [
        for (final e in settings.entries)
          _Row(_humanise(e.key), e.value is bool
              ? _yesNo(e.value)
              : (e.value is List ? _list(e.value) : e.value?.toString())),
      ]),
      _Section(l.nerdSectionStorage, [
        for (final e in storage.entries) ..._storageRows(e.key, _map(e.value)),
      ]),
      _Section(l.nerdSectionFeatures, [
        _Row(l.nerdFeatures, _list(server['features'])),
        _Row(l.nerdAuthVersions, _list(server['auth_versions'])),
      ]),
    ];
  }

  List<Widget> _units(dynamic raw) {
    final l = context.l10n;
    final units = (raw as List?) ?? const [];
    if (units.isEmpty) return [_Row(l.nerdUnits, l.nerdNoneConfigured)];
    final out = <Widget>[];
    for (final u in units.cast<Map<String, dynamic>>()) {
      final caps = _map(u['capabilities']);
      out.addAll([
        _Row(u['name']?.toString() ?? l.nerdUnitFallback, '${u['ip']}:${u['port']}'),
        _Row('  id', u['id']?.toString()),
        _Row('  ${l.nerdV3Credentials}', _yesNo(u['has_v3_credentials'])),
        _Row('  ${l.nerdConnectionCached}', _yesNo(u['connected'])),
        if (u['samples'] != null) _Row('  ${l.nerdHistorySamples}', u['samples'].toString()),
        if (caps.isNotEmpty) ...[
          _Row('  ${l.nerdModes}', _list(caps['operational_modes'])),
          _Row('  ${l.nerdSwing}', _list(caps['swing_modes'])),
          _Row('  ${l.nerdFanSpeeds}', _list(caps['fan_speeds'])),
          _Row('  ${l.nerdTempRange}', caps['min_target_temperature'] == null
              ? null
              : '${caps['min_target_temperature']}–${caps['max_target_temperature']} °C'),
          _Row('  ${l.nerdEcoTurbo}',
              '${_yesNo(caps['supports_eco'])} / ${_yesNo(caps['supports_turbo'])}'),
        ] else
          _Row('  ${l.nerdCapabilities}',
              l.nerdCapabilitiesNotCached),
      ]);
    }
    return out;
  }

  List<Widget> _devices(dynamic raw) {
    final l = context.l10n;
    final devices = (raw as List?) ?? const [];
    if (devices.isEmpty) return [_Row(l.nerdDevices, l.nerdNoneEnrolled)];
    final out = <Widget>[];
    for (final d in devices.cast<Map<String, dynamic>>()) {
      final expiresIn = d['expires_in_seconds'];
      out.addAll([
        _Row(d['label']?.toString() ?? l.nerdDeviceFallback,
            'auth v${d['auth_version']}${d['expired'] == true ? ' · ${l.nerdExpiredTag}' : ''}'),
        _Row('  id', d['token_id']?.toString()),
        _Row('  ${l.nerdEnrolled}', _when(d['created_at'])),
        _Row('  ${l.nerdLastUsed}', _when(d['last_used'])),
        _Row('  ${l.nerdExpires}', expiresIn == null
            ? l.nerdNever
            : l.nerdExpiresIn('${_when(d['expires_at'])}', '${_duration(expiresIn)}')),
      ]);
    }
    return out;
  }

  List<Widget> _storageRows(String name, Map<String, dynamic> f) {
    final l = context.l10n;
    if (f['exists'] != true) {
      return [_Row(name, l.nerdMissing('${f['path']}'))];
    }
    return [
      _Row(name, f['path']?.toString()),
      _Row('  ${l.nerdSizeMode}', '${_bytes(f['size_bytes'])} · ${f['mode']}'),
      _Row('  ${l.nerdModified}', _when(f['modified_at'])),
    ];
  }

  // --- helpers --------------------------------------------------------------

  Map<String, dynamic> _map(dynamic v) =>
      v is Map ? Map<String, dynamic>.from(v) : <String, dynamic>{};

  String? _list(dynamic v) {
    if (v is List) return v.isEmpty ? context.l10n.nerdNone : v.join(', ');
    return v?.toString();
  }

  String _yesNo(dynamic v) =>
      v == null ? '?' : (v == true ? context.l10n.nerdYes : context.l10n.nerdNo);

  String _byKind(dynamic v) {
    final m = _map(v);
    if (m.isEmpty) return context.l10n.nerdNone;
    return m.entries.map((e) => '${e.value} ${e.key}').join(', ');
  }

  String _humanise(String key) {
    final s = key.replaceAll('_', ' ');
    return s[0].toUpperCase() + s.substring(1);
  }

  String? _when(dynamic epoch) {
    if (epoch is! num) return null;
    final dt = DateTime.fromMillisecondsSinceEpoch((epoch * 1000).round()).toLocal();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${dt.year}-${two(dt.month)}-${two(dt.day)} '
        '${two(dt.hour)}:${two(dt.minute)}:${two(dt.second)}';
  }

  String? _duration(dynamic seconds) {
    if (seconds is! num) return null;
    var s = seconds.round().abs();
    final d = s ~/ 86400;
    s %= 86400;
    final h = s ~/ 3600;
    s %= 3600;
    final m = s ~/ 60;
    s %= 60;
    final l = context.l10n;
    if (d > 0) return l.nerdDurationDays(d, h, m);
    if (h > 0) return l.nerdDurationHours(h, m);
    if (m > 0) return l.nerdDurationMinutes(m, s);
    return l.nerdDurationSeconds(s);
  }

  String _offset(dynamic seconds) {
    if (seconds is! num) return '?';
    final sign = seconds < 0 ? '-' : '+';
    final total = seconds.abs() ~/ 60;
    return '$sign${(total ~/ 60).toString().padLeft(2, '0')}:'
        '${(total % 60).toString().padLeft(2, '0')}';
  }

  String? _bytes(dynamic v) {
    if (v is! num) return null;
    if (v < 1024) return '$v B';
    if (v < 1024 * 1024) return '${fmtDecimal(v / 1024, 1)} KiB';
    return '${fmtDecimal(v / 1024 / 1024, 1)} MiB';
  }

  /// The point of this screen is usually to paste it somewhere, so make that
  /// one tap rather than a screenshot marathon.
  void _copyAll() {
    final b = StringBuffer()
      ..writeln('Breeze ${AppInfo.version} on ${AppInfo.os} ${AppInfo.osVersion}')
      ..writeln('Dart ${AppInfo.dartVersion}')
      ..writeln('Server: ${AppScope.of(context).api?.baseUrl} '
          '(latency ${_latencyMs ?? '?'} ms)')
      ..writeln()
      ..writeln(const JsonEncoder.withIndent('  ').convert(_sys));
    Clipboard.setData(ClipboardData(text: b.toString()));
    Haptics.success();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(context.l10n.nerdCopied)),
    );
  }
}

class _WompWomp extends StatelessWidget {
  const _WompWomp({this.version});
  final String? version;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.sentiment_dissatisfied, size: 72, color: scheme.outline),
            const SizedBox(height: 20),
            Text(context.l10n.nerdWompWomp,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 12),
            Text(
              version == null
                  ? context.l10n.nerdNeedsNewer
                  : context.l10n.nerdServerTooOld(version!),
              textAlign: TextAlign.center,
              style: TextStyle(color: scheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}

class _Problem extends StatelessWidget {
  const _Problem({required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.cloud_off, size: 56, color: scheme.error),
            const SizedBox(height: 16),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 20),
            FilledButton.tonal(onPressed: onRetry, child: Text(context.l10n.nerdTryAgain)),
          ],
        ),
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section(this.title, this.rows);
  final String title;
  final List<Widget> rows;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 6),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title.toUpperCase(),
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: scheme.primary,
                      letterSpacing: 1.2,
                      fontWeight: FontWeight.w700,
                    )),
            const SizedBox(height: 8),
            ...rows,
          ],
        ),
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row(this.label, this.value);
  final String label;
  final String? value;

  @override
  Widget build(BuildContext context) {
    // A row with nothing to say is noise on a screen that's already dense.
    if (value == null || value!.isEmpty) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 4,
            child: Text(label,
                style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 13)),
          ),
          Expanded(
            flex: 6,
            child: SelectableText(
              value!,
              style: const TextStyle(fontSize: 13, fontFeatures: [
                FontFeature.tabularFigures(),
              ]),
            ),
          ),
        ],
      ),
    );
  }
}
