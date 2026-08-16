import 'dart:io';

import 'package:flutter/services.dart' show rootBundle;
import 'package:package_info_plus/package_info_plus.dart';

/// The app's own version and build facts, read at startup.
///
/// The version used to be a string literal in the About dialog, which is
/// exactly the kind of thing that goes stale: 2.2.1 shipped still calling
/// itself 2.2.0, because bumping `pubspec.yaml` doesn't touch a hardcoded
/// constant. Everything here is therefore *derived* — from the installed
/// package, from `Platform`, or from the shipped `pubspec.lock` — so nothing
/// on the Nerd screen can quietly disagree with what's actually running.
class AppInfo {
  AppInfo._();

  /// e.g. `2.2.5 (17)`. Empty until [load] completes; `main()` awaits it
  /// before the first frame, so the UI never sees the empty value.
  static String version = '';

  /// e.g. `2.2.5`, without the build number.
  static String shortVersion = '';

  static String packageName = '';
  static String buildNumber = '';

  /// Dart runtime, e.g. `3.10.2 (stable) on "android_arm64"`.
  static String get dartVersion => Platform.version;

  /// e.g. `Android 15 (API 35)` — whatever the platform reports.
  static String get osVersion => Platform.operatingSystemVersion;

  static String get os => Platform.operatingSystem;

  /// Resolved versions of the app's own dependencies, parsed from the
  /// `pubspec.lock` shipped as an asset.
  ///
  /// Shipping the lock file rather than a hand-written list is the whole
  /// point: the lock file *is* the resolved truth, so this can't drift the
  /// way a maintained constant would. Empty if the asset is missing.
  static Map<String, String> packages = const {};

  /// Dart/Flutter SDK constraints from the lock file's `sdks:` block.
  static Map<String, String> sdks = const {};

  static Future<void> load() async {
    try {
      final info = await PackageInfo.fromPlatform();
      shortVersion = info.version;
      buildNumber = info.buildNumber;
      packageName = info.packageName;
      version = '${info.version} (${info.buildNumber})';
    } catch (_) {
      // Never let a diagnostic detail stop the app from starting.
      shortVersion = '?';
      version = 'unknown';
    }
    try {
      _parseLock(await rootBundle.loadString('pubspec.lock'));
    } catch (_) {
      // Asset missing (or unreadable): the Nerd screen shows fewer rows.
    }
  }

  /// Minimal reader for the bits of `pubspec.lock` worth displaying.
  ///
  /// A full YAML parser would be a dependency for one screen. The lock file's
  /// shape is fixed and machine-generated, so matching `  name:` at two-space
  /// indent and the `version: "x.y.z"` under it is sufficient — and if the
  /// format ever changes, the result is missing rows, not a crash.
  static void _parseLock(String text) {
    final pkgs = <String, String>{};
    final sdkMap = <String, String>{};
    String? current;
    var inPackages = false;
    var inSdks = false;

    for (final raw in text.split('\n')) {
      final line = raw.replaceAll('\r', '');
      if (line.startsWith('packages:')) {
        inPackages = true;
        inSdks = false;
        continue;
      }
      if (line.startsWith('sdks:')) {
        inPackages = false;
        inSdks = true;
        continue;
      }
      if (inSdks) {
        final m = RegExp(r'^\s+(\w+):\s*"?([^"]+)"?\s*$').firstMatch(line);
        if (m != null) sdkMap[m.group(1)!] = m.group(2)!.trim();
        continue;
      }
      if (!inPackages) continue;

      final name = RegExp(r'^  (\S+):\s*$').firstMatch(line);
      if (name != null) {
        current = name.group(1);
        continue;
      }
      final ver = RegExp(r'^\s+version:\s*"?([^"]+)"?\s*$').firstMatch(line);
      if (ver != null && current != null) {
        pkgs[current] = ver.group(1)!.trim();
        current = null;
      }
    }
    packages = pkgs;
    sdks = sdkMap;
  }
}
