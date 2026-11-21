// Where the forensic build listens: every error Flutter or Dart can report,
// the app's lifecycle, the screen and the system settings changing, memory
// pressure, slow frames, every screen opened and closed, the network
// changing, and the app's own state (signed in or not, which address it is
// using). Started from main(), before anything else.

import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:ui' as ui;

import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

import '../app_controller.dart';
import '../app_info.dart';
import 'forensics.dart';
import 'native.dart';
import 'probes.dart';

final GlobalKey<NavigatorState> forensicNavigator = GlobalKey<NavigatorState>();

Future<void> forensicsBoot() async {
  final f = Forensics.I;
  f.log('boot', 'Breeze forensic build starting');
  FlutterError.onError = (details) {
    f.log('flutter', 'FlutterError: ${details.exceptionAsString()}${details.context == null ? '' : ' (${details.context})'}'
        '${details.library == null ? '' : ' in ${details.library}'}',
        level: Level.error, stack: details.stack);
    FlutterError.presentError(details);
  };
  ui.PlatformDispatcher.instance.onError = (error, stack) {
    f.log('dart', 'uncaught', level: Level.error, error: error, stack: stack);
    return true;
  };
  Isolate.current.addErrorListener(RawReceivePort((dynamic pair) {
    final list = pair as List;
    f.log('isolate', 'isolate error: ${list.first}', level: Level.error, stack: StackTrace.fromString('${list.last}'));
  }).sendPort);
  await f.start();
  await AppInfo.load();
  f.log('boot', 'Breeze ${AppInfo.version} (${AppInfo.buildNumber}) ${AppInfo.packageName}, ${Platform.operatingSystem} '
      '${Platform.operatingSystemVersion}, Dart ${Platform.version.split(' ').first}, session ${f.sessionName}');
  final prev = f.previous;
  if (prev != null) {
    f.log('boot', 'previous session ${prev.file}: last state "${prev.lastState}": ${prev.verdict}; ${prev.errors} errors',
        level: prev.lastState == 'resumed' || prev.lastState == 'inactive' ? Level.warn : Level.info);
  }
  await listenToNative();
  _Watcher().start();
}

class _Watcher with WidgetsBindingObserver {
  String _net = '';
  int _frames = 0;
  int _slow = 0;
  int _worstMs = 0;

  void start() {
    final b = WidgetsBinding.instance;
    b.addObserver(this);
    AppLifecycleListener(onStateChange: (s) {
      Forensics.I.lifecycle = s.name;
      Forensics.I.writeState();
      flog('lifecycle', s.name);
    });
    SchedulerBinding.instance.addTimingsCallback(_timings);
    _views('start');
    Timer.periodic(const Duration(seconds: 30), (_) => _tick());
    _tick();
  }

  void _timings(List<ui.FrameTiming> ts) {
    for (final t in ts) {
      _frames++;
      final ms = t.totalSpan.inMilliseconds;
      if (ms > 34) _slow++;
      if (ms > _worstMs) _worstMs = ms;
      if (ms > 250) {
        flog('frames', 'a frame took $ms ms (build ${t.buildDuration.inMilliseconds}, raster ${t.rasterDuration.inMilliseconds})',
            level: Level.warn);
      }
    }
  }

  Future<void> _tick() async {
    if (_slow > 0) {
      flog('frames', '$_frames frames in the last 30 s, $_slow slower than 34 ms, the worst $_worstMs ms', level: Level.debug);
    }
    _frames = _slow = _worstMs = 0;
    final rss = ProcessInfo.currentRss ~/ 1048576;
    final net = (await interfaces()).join(' | ');
    if (net != _net) {
      flog('network', 'interfaces: $net');
      _net = net;
    }
    flog('memory', '$rss MB resident', level: Level.debug);
  }

  void _views(String why) {
    for (final v in ui.PlatformDispatcher.instance.views) {
      flog('screen', '$why: ${(v.physicalSize / v.devicePixelRatio)} at ${v.devicePixelRatio}x, padding ${_dp(v.padding, v.devicePixelRatio)}, '
          'insets ${_dp(v.viewInsets, v.devicePixelRatio)}${v.displayFeatures.isEmpty ? '' : ', features ${v.displayFeatures}'}',
          level: Level.debug);
    }
  }

  @override
  void didChangeMetrics() => _views('metrics changed');

  @override
  void didChangeTextScaleFactor() => flog('system', 'text scale ${ui.PlatformDispatcher.instance.textScaleFactor}');

  @override
  void didChangePlatformBrightness() => flog('system', 'brightness ${ui.PlatformDispatcher.instance.platformBrightness}');

  @override
  void didChangeLocales(List<Locale>? locales) => flog('system', 'locales $locales');

  @override
  void didChangeAccessibilityFeatures() =>
      flog('system', 'accessibility ${ui.PlatformDispatcher.instance.accessibilityFeatures}');

  @override
  void didHaveMemoryPressure() => flog('memory', 'memory pressure at ${ProcessInfo.currentRss ~/ 1048576} MB', level: Level.warn);
}

/// Padding in logical pixels: left, top, right, bottom.
String _dp(ui.ViewPadding p, double dpr) => '${(p.left / dpr).toStringAsFixed(0)},${(p.top / dpr).toStringAsFixed(0)},'
    '${(p.right / dpr).toStringAsFixed(0)},${(p.bottom / dpr).toStringAsFixed(0)}';

/// Every screen opened, closed or replaced.
class ForensicObserver extends NavigatorObserver {
  String _name(Route<dynamic>? r) {
    if (r == null) return '-';
    final n = r.settings.name;
    if (n != null) return n;
    // MaterialPageRoute<..>(builder: ...) has no name: its type and the
    // widget it shows say enough.
    return r.runtimeType.toString();
  }

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      flog('nav', 'push ${_name(route)} over ${_name(previousRoute)}');

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      flog('nav', 'pop ${_name(route)} back to ${_name(previousRoute)}');

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) =>
      flog('nav', 'replace ${_name(oldRoute)} with ${_name(newRoute)}');

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) => flog('nav', 'remove ${_name(route)}');
}

/// The controller's transitions: the stage (loading, onboarding, pairing,
/// home), its error, the units, the server, and the address in use, which
/// moves to a fallback when the main one fails.
void watchController(AppController c) {
  AppStage? stage;
  String? error;
  int units = -1;
  Object? api;
  void check() {
    if (c.stage != stage) {
      flog('app', 'stage ${stage?.name ?? '-'} -> ${c.stage.name}');
      stage = c.stage;
    }
    if (c.error != error) {
      if (c.error != null) flog('app', 'error shown: ${c.error}', level: Level.warn);
      error = c.error;
    }
    if (c.units.length != units) {
      flog('app', '${c.units.length} units: ${c.units.map((u) => '${u.id} ${u.name}').join(', ')}');
      units = c.units.length;
    }
    final a = c.api;
    if (!identical(a, api)) {
      api = a;
      if (a == null) {
        flog('app', 'no server client');
      } else {
        flog('app', 'server client for ${a.baseUrl}, auth v${a.authVersion}, device credential ${a.hasDeviceCredential}');
        a.currentUrl.addListener(() => flog('app', 'now using ${a.currentUrl.value}${a.currentUrl.value == a.baseUrl ? ' (the main address)' : ' (a fallback)'}',
            level: a.currentUrl.value == a.baseUrl ? Level.info : Level.warn));
      }
    }
  }

  c.addListener(check);
  check();
}
