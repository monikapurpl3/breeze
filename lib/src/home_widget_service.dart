// Home-screen widget bridge.
//
// The native Android App Widget (see android/.../BreezeUnitWidgetProvider.kt)
// renders from data we stash via `home_widget`, and its buttons fire an
// interactive **background callback** — [interactiveCallback] below — which
// runs in a headless Flutter isolate, reuses the normal [ApiClient] +
// [SecureStore], performs the control, and pushes the fresh state back to the
// widget. So "power on from the home screen" works without opening the app.
//
// Everything here is best-effort: widget failures must never surface in, or
// break, the foreground app.

import 'dart:async';
import 'dart:convert';

import 'package:home_widget/home_widget.dart';
import 'package:workmanager/workmanager.dart';

import 'api_client.dart';
import 'models.dart';
import 'secure_store.dart';

const String _kRefreshTask = 'breeze-widget-refresh';

/// Fully-qualified name of the Android AppWidgetProvider we update.
const String kWidgetProvider = 'app.breeze.breeze.BreezeUnitWidgetProvider';

// Keys in the shared `HomeWidgetPreferences` store (read by the native side).
const String _kUnitList = 'unit_list'; // JSON [{id,name}] for the config picker
const String _kPaired = 'paired'; // "1" | "0"
String _stateKey(String unitId) => 'state.$unitId';

class HomeWidgetService {
  /// Register the interactive callback. Call once at startup.
  static Future<void> init() async {
    try {
      await HomeWidget.registerInteractivityCallback(interactiveCallback);
    } catch (_) {/* widgets are optional */}
  }

  /// Register a periodic background task (min 15 min on Android) that
  /// refreshes widget data even while the app is closed. Best-effort.
  static Future<void> registerBackgroundRefresh() async {
    try {
      await Workmanager().initialize(workmanagerDispatcher);
      await Workmanager().registerPeriodicTask(
        _kRefreshTask,
        _kRefreshTask,
        frequency: const Duration(minutes: 15),
        constraints: Constraints(networkType: NetworkType.connected),
        existingWorkPolicy: ExistingPeriodicWorkPolicy.update,
      );
    } catch (_) {/* periodic refresh is a nicety; ignore if unavailable */}
  }

  /// Push the current unit list + per-unit state to the widgets and redraw.
  static Future<void> sync({
    required List<UnitSummary> units,
    required Map<String, UnitState> states,
    required bool paired,
  }) async {
    try {
      final list = units.map((u) => {'id': u.id, 'name': u.name}).toList();
      await HomeWidget.saveWidgetData<String>(_kUnitList, jsonEncode(list));
      await HomeWidget.saveWidgetData<String>(_kPaired, paired ? '1' : '0');
      for (final u in units) {
        final s = states[u.id];
        if (s != null) {
          await HomeWidget.saveWidgetData<String>(_stateKey(u.id), jsonEncode(stateJson(s)));
        }
      }
      await HomeWidget.updateWidget(qualifiedAndroidName: kWidgetProvider);
    } catch (_) {/* never break the app over a widget */}
  }

  /// Compact wire form the native provider parses.
  static Map<String, dynamic> stateJson(UnitState s) => {
        'name': s.name,
        'online': s.online,
        'power': s.powerState,
        'target': s.targetTemperature,
        'mode': s.operationalMode,
        'fan': s.fanSpeed,
      };
}

double _clampTemp(double t) =>
    t < kMinTemp ? kMinTemp : (t > kMaxTemp ? kMaxTemp : t);

/// Runs in a background isolate when a widget button is tapped. The URI looks
/// like `homeWidget://control?action=power&unit=<id>&wid=<appWidgetId>`.
@pragma('vm:entry-point')
Future<void> interactiveCallback(Uri? uri) async {
  if (uri == null || uri.host != 'control') return;
  final action = uri.queryParameters['action'];
  final unitId = uri.queryParameters['unit'];
  if (action == null || unitId == null) return;

  // Build a client from stored credentials — this loads the v2 request
  // signer (or the legacy bearer token) so the isolate authenticates exactly
  // like the foreground app.
  final api = await ApiClient.fromStore(SecureStore());

  // No usable credentials → tell the widget to prompt for the app.
  if (api == null || !api.hasDeviceCredential) {
    await HomeWidget.saveWidgetData<String>(_kPaired, '0');
    await HomeWidget.updateWidget(qualifiedAndroidName: kWidgetProvider);
    return;
  }

  try {
    UnitState s = await api.getState(unitId);
    ClimateSettings? delta;
    switch (action) {
      case 'power':
        delta = ClimateSettings(powerState: !s.powerState);
        break;
      case 'tempUp':
        delta = ClimateSettings(targetTemperature: _clampTemp(s.targetTemperature + 0.5));
        break;
      case 'tempDown':
        delta = ClimateSettings(targetTemperature: _clampTemp(s.targetTemperature - 0.5));
        break;
      case 'refresh':
        delta = null; // just re-read the state we already fetched
        break;
      default:
        return;
    }
    if (delta != null) s = await api.control(unitId, delta);
    await HomeWidget.saveWidgetData<String>(_stateKey(unitId), jsonEncode(HomeWidgetService.stateJson(s)));
    await HomeWidget.saveWidgetData<String>(_kPaired, '1');
  } on ApiException catch (e) {
    if (e.unauthorized) {
      await HomeWidget.saveWidgetData<String>(_kPaired, '0');
    }
    // Otherwise keep the last-known state; a transient error shouldn't wipe it.
  } finally {
    api.close();
    await HomeWidget.updateWidget(qualifiedAndroidName: kWidgetProvider);
  }
}

/// WorkManager entry point — runs in a headless isolate on a schedule.
@pragma('vm:entry-point')
void workmanagerDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    await _refreshAllWidgets();
    return true;
  });
}

/// Refresh every unit's cached widget state (used by the periodic task).
/// Prefers the batch endpoint; falls back to per-unit on older servers.
Future<void> _refreshAllWidgets() async {
  final api = await ApiClient.fromStore(SecureStore());
  if (api == null || !api.hasDeviceCredential) {
    await HomeWidget.saveWidgetData<String>(_kPaired, '0');
    await HomeWidget.updateWidget(qualifiedAndroidName: kWidgetProvider);
    return;
  }
  try {
    final units = await api.listUnits();
    final states = <String, UnitState>{};
    try {
      final b = await api.listStates();
      for (final s in b.states) {
        states[s.id] = s;
      }
    } on ApiException {
      for (final u in units) {
        try {
          states[u.id] = await api.getState(u.id);
        } catch (_) {/* skip a unit we can't reach */}
      }
    }
    await HomeWidgetService.sync(units: units, states: states, paired: true);
  } on ApiException catch (e) {
    if (e.unauthorized) {
      await HomeWidget.saveWidgetData<String>(_kPaired, '0');
      await HomeWidget.updateWidget(qualifiedAndroidName: kWidgetProvider);
    }
  } finally {
    api.close();
  }
}
