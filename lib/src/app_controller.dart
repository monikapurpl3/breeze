// App-wide state: which stage we're in, the API client, and the units.
// A ChangeNotifier exposed via AppScope (InheritedNotifier).

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'api_client.dart';
import 'device_signer.dart';
import 'models.dart';
import 'secure_store.dart';

enum AppStage { loading, onboarding, pairing, home }

class AppController extends ChangeNotifier {
  final SecureStore store;
  AppController(this.store);

  AppStage stage = AppStage.loading;
  ApiClient? api;
  String? error;

  // --- display preferences (persisted, non-secret) ---
  static const _kTheme = 'pref_theme_mode'; // 'system' | 'light' | 'dark'
  static const _kUnit = 'pref_temp_unit';   // 'C' | 'F'
  ThemeMode themeMode = ThemeMode.system;
  String tempUnit = 'C';

  Future<void> _loadPrefs() async {
    final p = await SharedPreferences.getInstance();
    final t = p.getString(_kTheme);
    themeMode = t == 'light'
        ? ThemeMode.light
        : t == 'dark'
            ? ThemeMode.dark
            : ThemeMode.system;
    tempUnit = p.getString(_kUnit) == 'F' ? 'F' : 'C';
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    themeMode = mode;
    notifyListeners();
    final p = await SharedPreferences.getInstance();
    await p.setString(_kTheme, mode.name); // 'system' | 'light' | 'dark'
  }

  Future<void> setTempUnit(String unit) async {
    tempUnit = unit == 'F' ? 'F' : 'C';
    notifyListeners();
    final p = await SharedPreferences.getInstance();
    await p.setString(_kUnit, tempUnit);
  }

  // pairing transient state
  String? sessionId;
  String? userCode;
  int expiresIn = 0;
  String deviceLabel = 'Breeze';
  // Ed25519 keypair generated for the enrollment in progress; persisted only
  // once the server approves it (see pollPairing).
  DeviceSigner? _pendingSigner;

  List<UnitSummary> units = [];

  Future<void> init() async {
    await _loadPrefs();
    deviceLabel = (await store.deviceLabel) ?? 'Breeze';
    api = await ApiClient.fromStore(store);

    if (api == null) {
      _go(AppStage.onboarding);
      return;
    }
    if (api!.hasDeviceCredential) {
      _go(AppStage.home);
      // A device still on the legacy bearer scheme upgrades itself to
      // Ed25519 in the background — seamless, no re-pairing. Best-effort:
      // an older server or a transient failure just leaves it on v1
      // (which still works) to retry next launch.
      if (api!.authVersion < 2) unawaited(attemptUpgrade());
      return;
    }
    // Have server+key but no device credential (e.g. after unpair): pair.
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
    // New devices enroll straight onto v2: generate a keypair and register
    // its public half. The private key stays on-device and is persisted only
    // once the server approves (pollPairing).
    _pendingSigner = await DeviceSigner.generate();
    final r = await api!.enrollStart(
      deviceLabel, publicKey: await _pendingSigner!.publicKeyB64());
    sessionId = r['session_id'] as String;
    userCode = r['user_code'] as String;
    expiresIn = (r['expires_in'] as num).toInt();
    error = null;
    _go(AppStage.pairing);
  }

  Future<void> restartEnrollment() => _startEnrollment();

  /// One poll tick. Returns the status string; on approval, persists the
  /// device credential (v2 keypair, or a v1 token from an older server) and
  /// moves home.
  Future<String> pollPairing() async {
    final r = await api!.enrollPoll(sessionId!);
    final status = r['status'] as String;
    if (status == 'approved') {
      final av = (r['auth_version'] as num?)?.toInt() ?? 1;
      if (av >= 2 && _pendingSigner != null) {
        final signer = _pendingSigner!.withKeyId(r['token_id'] as String);
        await store.saveV2(await signer.seedB64(), signer.keyId);
        api!.adoptSigner(signer);
      } else {
        // Older server without v2: fall back to the bearer token it issued.
        final token = r['device_token'] as String;
        await store.saveToken(token);
        api!.deviceToken = token;
        api!.authVersion = 1;
      }
      _pendingSigner = null;
      _go(AppStage.home);
    }
    return status;
  }

  /// Upgrade an enrolled v1 device to v2 (Ed25519) in place, keeping the same
  /// server-side identity. Returns true on success. Safe to call when already
  /// on v2 (no-op) or when the server is too old (returns false, stays v1).
  Future<bool> attemptUpgrade() async {
    if (api == null || api!.authVersion >= 2) return api?.authVersion == 2;
    try {
      final info = await api!.serverInfo();
      final versions = ((info['auth_versions'] as List?) ?? const [])
          .map((e) => (e as num).toInt());
      if (!versions.contains(2)) return false; // server predates v2
      final signer = await DeviceSigner.generate();
      final res = await api!.upgradeToV2(await signer.publicKeyB64());
      final bound = signer.withKeyId(res['token_id'] as String);
      await store.saveV2(await bound.seedB64(), bound.keyId);
      api!.adoptSigner(bound);
      return true;
    } catch (_) {
      return false; // stay on v1; retried next launch
    }
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
