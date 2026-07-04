// App-wide state: which stage we're in, the API client, and the units.
// A ChangeNotifier exposed via AppScope (InheritedNotifier).

import 'package:flutter/widgets.dart';

import 'api_client.dart';
import 'models.dart';
import 'secure_store.dart';

enum AppStage { loading, onboarding, pairing, home }

class AppController extends ChangeNotifier {
  final SecureStore store;
  AppController(this.store);

  AppStage stage = AppStage.loading;
  ApiClient? api;
  String? error;

  // pairing transient state
  String? sessionId;
  String? userCode;
  int expiresIn = 0;
  String deviceLabel = 'Breeze';

  List<UnitSummary> units = [];

  Future<void> init() async {
    final url = await store.serverUrl;
    final key = await store.apiKey;
    final token = await store.deviceToken;
    deviceLabel = (await store.deviceLabel) ?? 'Breeze';

    if (url == null || key == null) {
      _go(AppStage.onboarding);
      return;
    }
    api = ApiClient(baseUrl: url, apiKey: key, deviceToken: token);
    if (token != null) {
      _go(AppStage.home);
      return;
    }
    // Have server+key but no token (e.g. after unpair): jump to pairing.
    try {
      await _startEnrollment();
    } catch (e) {
      error = e.toString();
      _go(AppStage.onboarding);
    }
  }

  void _go(AppStage s) {
    stage = s;
    notifyListeners();
  }

  /// Called from onboarding: validate server+key by starting enrollment.
  Future<void> connect(String rawUrl, String key, String label) async {
    final url = ApiClient.normalizeUrl(rawUrl);
    deviceLabel = label.trim().isEmpty ? 'Breeze' : label.trim();
    api = ApiClient(baseUrl: url, apiKey: key.trim());
    await _startEnrollment(); // throws on bad key / unreachable
    await store.saveConnection(url, key.trim(), deviceLabel);
  }

  Future<void> _startEnrollment() async {
    final r = await api!.enrollStart(deviceLabel);
    sessionId = r['session_id'] as String;
    userCode = r['user_code'] as String;
    expiresIn = (r['expires_in'] as num).toInt();
    error = null;
    _go(AppStage.pairing);
  }

  Future<void> restartEnrollment() => _startEnrollment();

  /// One poll tick. Returns the status string; on approval, stores the
  /// token and moves home.
  Future<String> pollPairing() async {
    final r = await api!.enrollPoll(sessionId!);
    final status = r['status'] as String;
    if (status == 'approved') {
      final token = r['device_token'] as String;
      await store.saveToken(token);
      api!.deviceToken = token;
      _go(AppStage.home);
    }
    return status;
  }

  Future<void> refreshUnits() async {
    units = await api!.listUnits();
    notifyListeners();
  }

  /// A 401 anywhere means the token is gone/expired — drop it and re-pair.
  Future<void> handleUnauthorized() async {
    await store.clearToken();
    api!.deviceToken = null;
    try {
      await _startEnrollment();
    } catch (e) {
      error = e.toString();
      _go(AppStage.onboarding);
    }
  }

  Future<void> unpair() => handleUnauthorized();

  Future<void> changeServer() async {
    await store.clearAll();
    api?.close();
    api = null;
    units = [];
    error = null;
    _go(AppStage.onboarding);
  }
}
