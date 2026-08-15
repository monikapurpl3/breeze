import 'package:package_info_plus/package_info_plus.dart';

/// The app's own version, read from the installed package at startup.
///
/// This used to be a string literal in the About dialog, which is exactly the
/// kind of thing that goes stale: 2.2.1 shipped still calling itself 2.2.0,
/// because bumping `pubspec.yaml` doesn't touch a hardcoded constant. Reading
/// it from the package means `pubspec.yaml` is the single source of truth and
/// the two can't drift again.
class AppInfo {
  AppInfo._();

  /// e.g. `2.2.1 (16)`. Empty until [load] completes; `main()` awaits it
  /// before the first frame, so the UI never sees the empty value.
  static String version = '';

  /// e.g. `2.2.1`, without the build number.
  static String shortVersion = '';

  static Future<void> load() async {
    try {
      final info = await PackageInfo.fromPlatform();
      shortVersion = info.version;
      version = '${info.version} (${info.buildNumber})';
    } catch (_) {
      // Never let a diagnostic detail stop the app from starting.
      shortVersion = '?';
      version = 'unknown';
    }
  }
}
