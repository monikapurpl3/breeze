// The Android-only parts stay quiet on an iPhone: the home-screen widget and
// its background refresh (whose iOS plugins need setup the iOS build doesn't
// have, and crash natively without it), and the licences of Android libraries
// the iOS build doesn't ship.
import 'package:breeze/src/home_widget_service.dart';
import 'package:breeze/src/models.dart';
import 'package:breeze/src/native_licenses.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const _workmanager = 'dev.flutter.pigeon.workmanager_platform_interface.WorkmanagerHostApi';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // Every message the widget and background plugins would send to native code.
  late List<String> calls;

  setUp(() {
    calls = <String>[];
    final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(const MethodChannel('home_widget'), (c) async {
      calls.add('home_widget.${c.method}');
      return true;
    });
    for (final m in ['initialize', 'registerPeriodicTask']) {
      messenger.setMockMessageHandler('$_workmanager.$m', (_) async {
        calls.add('workmanager.$m');
        return const StandardMessageCodec().encodeMessage(<Object?>[]);
      });
    }
  });

  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(const MethodChannel('home_widget'), null);
    for (final m in ['initialize', 'registerPeriodicTask']) {
      messenger.setMockMessageHandler('$_workmanager.$m', null);
    }
  });

  Future<void> everything() async {
    await HomeWidgetService.init();
    await HomeWidgetService.registerBackgroundRefresh();
    await HomeWidgetService.sync(
      units: [UnitSummary(id: 'u1', name: 'Bedroom', ip: '192.0.2.10')],
      states: const {},
      paired: true,
    );
  }

  test('on Android the widget is fed', () async {
    // The control for the test below: the mocks do see the plugin's calls.
    expect(HomeWidgetService.supported, isTrue);
    await everything();
    expect(calls, contains('home_widget.saveWidgetData'));
    expect(calls, contains('home_widget.updateWidget'));
  });

  test('on iOS nothing reaches the widget or background plugins', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    expect(HomeWidgetService.supported, isFalse);
    await everything();
    expect(calls, isEmpty);
  });

  test('on iOS the Android libraries are not in the licence page', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    LicenseRegistry.reset();
    registerNativeLicenses();
    final packages = <String>[];
    await for (final entry in LicenseRegistry.licenses) {
      packages.addAll(entry.packages);
    }
    expect(packages, isNot(contains('androidx.car.app:app')));
  });
}
