// What the app holds and what the device says, at one moment, as text: the
// app and the build, the device, the provisioning profile, the screen, every
// preference, the keychain (names and fingerprints, never values), the files
// in the app's container, the process, the network, and how the last session
// ended. And the export: that, the probes, this session's log and the last
// one's, and whatever crash reports iOS has delivered, in one file.

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../app_controller.dart';
import '../app_info.dart';
import 'forensics.dart';
import 'http_log.dart';
import 'native.dart';
import 'probes.dart';

void _section(StringBuffer b, String title) => b
  ..writeln()
  ..writeln('### $title');

void _map(StringBuffer b, Map<String, Object?> m) {
  final keys = m.keys.toList()..sort();
  for (final k in keys) {
    final v = m[k];
    if (v is Map) {
      b.writeln('  $k:');
      final inner = v.keys.map((e) => '$e').toList()..sort();
      for (final ik in inner) {
        b.writeln('    $ik: ${v[ik]}');
      }
    } else if (v is List) {
      b.writeln('  $k: (${v.length})');
      for (final x in v) {
        b.writeln('    - $x');
      }
    } else {
      b.writeln('  $k: $v');
    }
  }
}

Future<void> _files(StringBuffer b, String label, Directory? d, {int depth = 4}) async {
  if (d == null || !d.existsSync()) {
    b.writeln('  $label: (none)');
    return;
  }
  b.writeln('  $label: ${d.path}');
  var n = 0;
  var total = 0;
  try {
    await for (final e in d.list(recursive: true, followLinks: false)) {
      final rel = e.path.substring(d.path.length);
      if ('/'.allMatches(rel).length > depth) continue;
      if (e is File) {
        final st = e.statSync();
        total += st.size;
        if (n++ < 400) b.writeln('    $rel  ${st.size} B  ${st.modified.toIso8601String().substring(0, 19)}');
      }
    }
  } catch (e) {
    b.writeln('    (listing stopped: $e)');
  }
  b.writeln('    = $n files, $total B${n > 400 ? ' (first 400 listed)' : ''}');
}

Future<String> snapshot(AppController c) async {
  final b = StringBuffer()..writeln('Breeze forensic snapshot, ${DateTime.now().toIso8601String()}');
  final f = Forensics.I;

  _section(b, 'App');
  b
    ..writeln('  version ${AppInfo.version} (build ${AppInfo.buildNumber}), ${AppInfo.packageName}')
    ..writeln('  mode ${kReleaseMode ? 'release' : kProfileMode ? 'profile' : 'debug'}, forensics $kForensics')
    ..writeln('  Dart ${Platform.version}')
    ..writeln('  OS ${Platform.operatingSystem} ${Platform.operatingSystemVersion}, ${Platform.numberOfProcessors} CPUs, locale ${Platform.localeName}')
    ..writeln('  session ${f.sessionName}, ${DateTime.now().difference(f.started).inSeconds} s old, '
        '${f.errorCount} errors, ${f.warnCount} warnings')
    ..writeln('  memory: ${ProcessInfo.currentRss ~/ 1048576} MB resident now, ${ProcessInfo.maxRss ~/ 1048576} MB at most');

  _section(b, 'Device (iOS)');
  _map(b, await nativeInfo());

  _section(b, 'Provisioning profile (how this copy was signed)');
  final prov = await provisioning();
  _map(b, prov);
  final expires = DateTime.tryParse('${prov['expires'] ?? ''}');
  if (expires != null) {
    final left = expires.difference(DateTime.now());
    b.writeln('  => ${left.isNegative ? 'EXPIRED: iOS will not start this copy until it is signed again' : 'expires in ${left.inDays} days ${left.inHours % 24} h: sign it again before then'}');
  }

  _section(b, 'Screen and accessibility');
  final d = ui.PlatformDispatcher.instance;
  for (final v in d.views) {
    b.writeln('  view ${v.viewId}: ${v.physicalSize} px at ${v.devicePixelRatio}x = '
        '${(v.physicalSize / v.devicePixelRatio)} logical; padding ${v.padding}; viewPadding ${v.viewPadding}; '
        'insets ${v.viewInsets}; features ${v.displayFeatures}');
  }
  b
    ..writeln('  brightness ${d.platformBrightness}, text scale ${d.textScaleFactor}, 24-hour ${d.alwaysUse24HourFormat}')
    ..writeln('  accessibility ${d.accessibilityFeatures}')
    ..writeln('  locales ${d.locales.join(', ')}');

  _section(b, 'App state');
  final api = c.api;
  b
    ..writeln('  stage ${c.stage}${c.error == null ? '' : ', error: ${c.error}'}')
    ..writeln('  server ${api?.baseUrl ?? '(none)'}, in use ${api?.currentUrl.value ?? '-'}, auth v${api?.authVersion ?? '-'}, '
        'device credential ${api?.hasDeviceCredential ?? false}, clock offset ${api?.clockOffsetSeconds ?? 0} s')
    ..writeln('  units (${c.units.length}): ${c.units.map((u) => '${u.id} "${u.name}" ${u.ip}').join('; ')}')
    ..writeln('  theme ${c.themeMode}, AMOLED ${c.pureBlack}, unit ${c.tempUnit}, beep ${c.beep}, language ${c.language ?? 'the phone\'s'}, '
        'last unit ${c.lastUnitId}')
    ..writeln('  saved servers (${c.profiles.length}):');
  for (final p in c.profiles) {
    b.writeln('    ${p.id} "${p.name}" ${p.url} auth v${p.authVersion}, credential ${p.hasCredential}, device "${p.label}"');
  }

  _section(b, 'Preferences (SharedPreferences, nothing secret is kept here)');
  try {
    final p = await SharedPreferences.getInstance();
    final keys = p.getKeys().toList()..sort();
    for (final k in keys) {
      b.writeln('  $k = ${p.get(k)}');
    }
  } catch (e) {
    b.writeln('  unreadable: $e');
  }

  _section(b, 'Keychain, as the app reads it (values never: length and fingerprint)');
  try {
    for (final l in await c.store.forensicInventory()) {
      b.writeln('  $l');
    }
    b.writeln('  (p_<server>_<field>: url, api_key, token = v1 credential, seed + key_id = v2 credential, label = device name)');
  } catch (e) {
    b.writeln('  FAILED: $e  <- the keychain itself refuses: locked, or written by another signing team');
  }

  _section(b, 'Keychain, as iOS lists it (attributes only)');
  final kc = await keychainItems();
  final items = kc['items'];
  b.writeln('  status ${kc['status']} ${kc['statusText'] ?? ''}');
  if (items is List) {
    for (final it in items) {
      if (it is Map) {
        b.writeln('  ${it['account']}  service ${it['service']}, ${accessibilityName('${it['accessible']}')}, '
            'group ${it['accessGroup']}, sync ${it['synchronizable']}, created ${it['created']}, modified ${it['modified']}');
      }
    }
  } else {
    _map(b, kc);
  }

  _section(b, 'Files in the app\'s container');
  Future<Directory?> safe(Future<Directory> Function() get) async {
    try {
      return await get();
    } catch (_) {
      return null;
    }
  }

  await _files(b, 'Documents', await safe(getApplicationDocumentsDirectory));
  await _files(b, 'Library/Application Support', await safe(getApplicationSupportDirectory));
  await _files(b, 'Library', await safe(getLibraryDirectory));
  await _files(b, 'tmp', await safe(getTemporaryDirectory), depth: 2);

  _section(b, 'Network');
  for (final l in await interfaces()) {
    b.writeln('  $l');
  }
  final h = HttpRecorder.I;
  b.writeln('  HTTP this session: ${h.exchanges.length} kept, ${h.failures} failed');
  for (final e in h.exchanges.reversed.take(40)) {
    b.writeln('    ${e.at.toIso8601String().substring(11, 19)} ${e.summary}${e.error == null ? '' : ': ${e.error}'}');
  }

  _section(b, 'The previous session');
  final prev = f.previous;
  if (prev == null) {
    b.writeln('  none (this is the first)');
  } else {
    b
      ..writeln('  ${prev.file}: last state "${prev.lastState}": ${prev.verdict}; ${prev.errors} errors')
      ..writeln('  its last lines:');
    for (final l in prev.lastLines) {
      b.writeln('    $l');
    }
  }

  _section(b, 'Crash reports and diagnostics delivered by iOS');
  final dir = f.dir;
  final reports = dir == null
      ? <File>[]
      : (dir.listSync().whereType<File>().where((x) {
          final n = x.uri.pathSegments.last;
          return n.startsWith('metrickit-') || n.startsWith('native-crash-');
        }).toList()
        ..sort((a, b) => a.path.compareTo(b.path)));
  if (reports.isEmpty) {
    b.writeln('  none here. iOS also keeps its own: Settings > Privacy & Security > Analytics & Improvements > '
        'Analytics Data, files named Runner-…');
  }
  for (final r in reports) {
    b.writeln('  ${r.uri.pathSegments.last} (${r.lengthSync()} B)');
  }
  return b.toString();
}

/// The addresses the app would try, in order, for the probes.
Future<List<String>> probeTargets(AppController c) async {
  final urls = <String>[];
  final api = c.api;
  if (api != null) urls.add(api.baseUrl);
  try {
    final main = await c.store.serverUrl;
    if (main != null && !urls.contains(main)) urls.add(main);
    for (final a in await c.store.alternateUrls) {
      if (!urls.contains(a)) urls.add(a);
    }
  } catch (e) {
    flog('probe', 'reading the saved addresses failed', level: Level.warn, error: e);
  }
  return urls;
}

/// One file with everything, in Documents/forensics (the Files app shows
/// it). Returns it.
Future<File> exportBundle(AppController c) async {
  final f = Forensics.I;
  f.mark('export started');
  final b = StringBuffer()
    ..writeln(await snapshot(c))
    ..writeln()
    ..writeln('### Probes')
    ..writeln(await runProbes(await probeTargets(c)));
  b
    ..writeln()
    ..writeln('### This session\'s log');
  for (final e in f.entries) {
    b.writeln(e.line);
  }
  final prev = f.previous;
  final dir = f.dir ?? await getTemporaryDirectory();
  if (prev != null) {
    final file = File('${dir.path}/${prev.file}');
    b
      ..writeln()
      ..writeln('### The previous session\'s log (${prev.file})');
    if (file.existsSync()) b.writeln(file.readAsStringSync());
  }
  for (final r in dir.listSync().whereType<File>().where((x) {
    final n = x.uri.pathSegments.last;
    return n.startsWith('metrickit-') || n.startsWith('native-crash-') || n.startsWith('native-');
  })) {
    b
      ..writeln()
      ..writeln('### ${r.uri.pathSegments.last}')
      ..writeln(r.readAsStringSync());
  }
  final stamp = DateTime.now().toIso8601String().substring(0, 19).replaceAll(':', '').replaceAll('-', '').replaceAll('T', '-');
  final out = File('${dir.path}/export-$stamp.txt');
  await out.writeAsString(b.toString(), flush: true);
  f.log('forensics', 'exported ${out.path} (${out.lengthSync()} B)');
  return out;
}
