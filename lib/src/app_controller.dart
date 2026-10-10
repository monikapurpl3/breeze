// App-wide state: which stage we're in, the API client, and the units.
// A ChangeNotifier exposed via AppScope (InheritedNotifier).

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'api_client.dart';
import 'device_signer.dart';
import 'haptics.dart';
import 'internal_prefs.dart';
import 'widgets/loading_cat.dart';
import 'models.dart';
import 'secure_store.dart';
import 'device_name.dart';

enum AppStage { loading, onboarding, pairing, home }

class AppController extends ChangeNotifier {
  final SecureStore store;
  AppController(this.store);

  AppStage stage = AppStage.loading;
  ApiClient? api;
  String? error;

  // --- display preferences (persisted, non-secret) ---
  static const _kTheme = 'pref_theme_mode'; // 'system' | 'light' | 'dark'
  static const _kUnit = 'pref_temp_unit'; // 'C' | 'F'
  static const _kBeep = 'pref_beep'; // whether commands make the unit chirp
  static const _kLastUnit =
      'pref_last_unit_id'; // last unit page the user was on
  ThemeMode themeMode = ThemeMode.system;
  String tempUnit = 'C';
  bool beep = false;
  // Which unit page to restore on launch (by unit id, so it survives
  // reordering; the home screen falls back gracefully if it's gone). Null =
  // no preference yet → start on the first unit.
  String? lastUnitId;

  /// The Nerd screen's Internal tab. See [InternalPrefs].
  InternalPrefs internal = InternalPrefs();

  Duration get _timeout => Duration(seconds: internal.timeoutSeconds);

  /// Push the settings that live outside this controller to where they are
  /// read: haptics and cat facts are static, the timeout is on the client.
  void _applyInternal() {
    Haptics.enabled = internal.haptics;
    CatFacts.custom = internal.catFacts;
    CatFacts.includeBuiltIn = internal.builtInCatFacts;
    api?.timeout = _timeout;
    // Requests are timed only while the latency readout is switched on.
    api?.measureLatency = internal.showLatency;
  }

  /// Change one or more internal settings: [edit] mutates [internal], then
  /// everything that depends on it is updated and the change is saved.
  Future<void> updateInternal(void Function(InternalPrefs p) edit) async {
    edit(internal);
    _applyInternal();
    notifyListeners();
    await internal.save();
  }

  Future<void> resetInternal() async {
    internal = await InternalPrefs.reset();
    _applyInternal();
    notifyListeners();
  }

  Future<void> _loadPrefs() async {
    internal = await InternalPrefs.load();
    _applyInternal();
    final p = await SharedPreferences.getInstance();
    final t = p.getString(_kTheme);
    themeMode = t == 'light'
        ? ThemeMode.light
        : t == 'dark'
        ? ThemeMode.dark
        : ThemeMode.system;
    tempUnit = p.getString(_kUnit) == 'F' ? 'F' : 'C';
    beep = p.getBool(_kBeep) ?? false;
    lastUnitId = p.getString(_kLastUnit);
  }

  /// Remember the unit page the user last viewed. Purely persistence — no
  /// [notifyListeners], so swiping between units never rebuilds the app tree.
  Future<void> setLastUnitId(String? id) async {
    if (id == lastUnitId) return;
    lastUnitId = id;
    final p = await SharedPreferences.getInstance();
    if (id == null) {
      await p.remove(_kLastUnit);
    } else {
      await p.setString(_kLastUnit, id);
    }
  }

  Future<void> setBeep(bool value) async {
    beep = value;
    notifyListeners();
    final p = await SharedPreferences.getInstance();
    await p.setBool(_kBeep, value);
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

  /// Falls back to a generated name rather than a constant: a household that
  /// pairs several phones used to end up with a device list of identical
  /// "Breeze" rows, impossible to tell apart when revoking one.
  String deviceLabel = DeviceName.suggest();
  // Ed25519 keypair generated for the enrollment in progress; persisted only
  // once the server approves it (see pollPairing).
  DeviceSigner? _pendingSigner;

  List<UnitSummary> units = [];

  /// Every saved server. Switching between them is credential-preserving —
  /// see [switchProfile].
  List<ServerProfile> profiles = [];
  String? activeProfileId;

  Future<void> reloadProfiles() async {
    profiles = await store.profiles();
    activeProfileId = await store.activeProfileId;
    notifyListeners();
  }

  Future<void> init() async {
    await _loadPrefs();
    // Lift a pre-2.2.5 single-server install into a profile before anything
    // reads a credential, or the app would look unpaired to an upgrader.
    await store.migrate();
    await reloadProfiles();
    deviceLabel = (await store.deviceLabel) ?? DeviceName.suggest();
    api = await ApiClient.fromStore(store, timeout: _timeout);
    _applyInternal();

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
      unawaited(_refreshLanIfOn());
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
    deviceLabel = label.trim().isEmpty ? DeviceName.suggest() : label.trim();
    api = ApiClient(baseUrl: url, apiKey: key.trim(), timeout: _timeout);
    _applyInternal();
    await _startEnrollment(); // throws on bad key / unreachable
    // Only now is the profile written (and made active): a server we couldn't
    // reach, or a wrong key, must not leave a dead entry in the list.
    await store.saveConnection(url, key.trim(), deviceLabel);
    addingServer = false;
    await reloadProfiles();
  }

  /// Which auth version the pairing in progress asks for. 2 unless the Nerd
  /// screen asked for 1.
  int _enrollVersion = 2;

  Future<void> _startEnrollment({int? authVersion}) async {
    _enrollVersion = authVersion ?? _enrollVersion;
    if (_enrollVersion >= 2) {
      // New devices enroll straight onto v2: generate a keypair and register
      // its public half. The private key stays on-device and is persisted
      // only once the server approves (pollPairing).
      _pendingSigner = await DeviceSigner.generate();
    } else {
      // v1, asked for from the Nerd screen: the server issues a bearer token.
      _pendingSigner = null;
    }
    final r = await api!.enrollStart(
      deviceLabel,
      publicKey: _pendingSigner == null ? null : await _pendingSigner!.publicKeyB64(),
    );
    sessionId = r['session_id'] as String;
    userCode = r['user_code'] as String;
    expiresIn = (r['expires_in'] as num).toInt();
    error = null;
    _go(AppStage.pairing);
  }

  Future<void> restartEnrollment() => _startEnrollment();

  /// Pair this device again, from the Nerd screen: with [authVersion] 1 or 2,
  /// under a new [label].
  ///
  /// The new pairing is started first, and the current credential is kept
  /// until an admin approves the new one -- so a server that can't be reached
  /// right now leaves the device as it was, rather than with no credential at
  /// all. The old entry stays in the server's device list until revoked
  /// there. A v1 choice also stops the background upgrade to v2, which would
  /// otherwise undo it on the next launch.
  Future<void> pairAgain({required int authVersion, required String label}) async {
    final name = label.trim().isEmpty ? DeviceName.suggest() : label.trim();
    final previous = deviceLabel;
    deviceLabel = name;
    try {
      await _startEnrollment(authVersion: authVersion);
    } catch (_) {
      deviceLabel = previous;
      rethrow;
    }
    await store.saveLabel(name);
    await store.setPinnedToV1(authVersion == 1);
  }

  /// One poll tick. Returns the status string; on approval, persists the
  /// device credential (v2 keypair, or a v1 token from an older server) and
  /// moves home.
  Future<String> pollPairing() async {
    final r = await api!.enrollPoll(sessionId!);
    final status = r['status'] as String;
    if (status == 'approved') {
      final av = (r['auth_version'] as num?)?.toInt() ?? 1;
      // Whatever was there before goes: pairing again from the Nerd screen
      // keeps the old credential working until this moment.
      await store.clearToken();
      _enrollVersion = 2;
      if (av >= 2 && _pendingSigner != null) {
        final signer = _pendingSigner!.withKeyId(r['token_id'] as String);
        await store.saveV2(await signer.seedB64(), signer.keyId);
        await store.setPinnedToV1(false);
        api!.adoptSigner(signer);
      } else {
        // Older server without v2: fall back to the bearer token it issued.
        final token = r['device_token'] as String;
        await store.saveToken(token);
        api!.deviceToken = token;
        api!.authVersion = 1;
      }
      _pendingSigner = null;
      addingServer = false;
      await reloadProfiles();   // that profile now shows as paired
      _go(AppStage.home);
    }
    return status;
  }

  /// Upgrade an enrolled v1 device to v2 (Ed25519) in place, keeping the same
  /// server-side identity. Returns true on success. Safe to call when already
  /// on v2 (no-op) or when the server is too old (returns false, stays v1).
  Future<bool> attemptUpgrade() async {
    if (api == null || api!.authVersion >= 2) return api?.authVersion == 2;
    // Paired as v1 on purpose, from the Nerd screen: stay there.
    if (await store.pinnedToV1) return false;
    try {
      final info = await api!.serverInfo();
      final versions = ((info['auth_versions'] as List?) ?? const []).map(
        (e) => (e as num).toInt(),
      );
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

  /// Consecutive 401s that weren't explicitly "your credential is dead".
  int _unexplained401s = 0;

  /// How many unexplained 401s in a row before we give up on the credential.
  /// Re-pairing is destructive (it deletes this device's Ed25519 private key)
  /// and needs an admin on the LAN, so it must never be the reaction to a
  /// one-off.
  static const _kMax401sBeforeRepair = 3;

  /// React to a 401.
  ///
  /// This used to unconditionally wipe the credential and demand re-pairing,
  /// which cost several users their access: a *transient* rejection (a phone
  /// whose clock had drifted past the server's 60 s window) deleted a
  /// perfectly good private key, and because enrolment is LAN-only, anyone
  /// away from home then couldn't recover and landed on the onboarding screen
  /// with the server forgotten — "the app lost my server".
  ///
  /// Now: the client itself retries genuinely transient failures (see
  /// [ApiClient]), so anything arriving here is at least suspicious — but we
  /// still only re-pair when the server *says* the credential is finished, or
  /// after several in a row from a server too old to tell us.
  /// Returns true if the credential was discarded.
  Future<bool> handleUnauthorized([ApiException? e]) async {
    final definitive = e?.credentialRejected ?? false;
    if (!definitive) {
      _unexplained401s++;
      if (_unexplained401s < _kMax401sBeforeRepair) {
        // Keep the credential and let the caller back off and retry.
        notifyListeners();
        return false;
      }
    }
    _unexplained401s = 0;
    await _repair();
    return true;
  }

  /// Discard the device credential and start pairing again.
  Future<void> _repair() async {
    await store.clearToken();
    api!.deviceToken = null;
    api!.signer = null;
    api!.authVersion = 1;
    try {
      await _startEnrollment();
    } catch (e) {
      error = e.toString();
      _go(AppStage.onboarding);
    }
  }

  /// Any successful authenticated call clears the suspicion counter.
  void noteAuthSuccess() => _unexplained401s = 0;

  Future<void> unpair() => _repair();

  /// Point the app at another saved server. No re-pairing: that server's
  /// credential is already in the keystore, so this is a pointer move plus a
  /// fresh client. Falls back to pairing only if the stored credential for
  /// the target is missing (e.g. it was revoked server-side).
  Future<void> switchProfile(String id) async {
    if (id == activeProfileId) return;
    await store.setActiveProfile(id);
    api?.close();
    units = [];
    error = null;
    lastUnitId = null;          // unit ids are per-server; don't carry one over
    deviceLabel = (await store.deviceLabel) ?? DeviceName.suggest();
    api = await ApiClient.fromStore(store, timeout: _timeout);
    _applyInternal();
    await reloadProfiles();

    if (api == null) {
      _go(AppStage.onboarding);
      return;
    }
    if (api!.hasDeviceCredential) {
      _go(AppStage.home);
      unawaited(refreshUnits());
      if (api!.authVersion < 2) unawaited(attemptUpgrade());
      unawaited(_refreshLanIfOn());
      return;
    }
    try {
      await _startEnrollment();
    } catch (e) {
      error = e.toString();
      _go(AppStage.onboarding);
    }
  }

  /// Start adding a *new* server without disturbing the current one: the
  /// onboarding screen writes a new profile only once pairing succeeds.
  void beginAddServer() {
    addingServer = true;
    error = null;
    _go(AppStage.onboarding);
  }

  /// True while onboarding is adding an extra server rather than doing
  /// first-run setup — the difference is whether Cancel has somewhere to go.
  bool addingServer = false;

  void cancelAddServer() {
    addingServer = false;
    error = null;
    _go(api?.hasDeviceCredential == true ? AppStage.home : AppStage.onboarding);
  }

  /// Forget one server. If it was the last, the app returns to first-run
  /// onboarding; otherwise it switches to whichever remains.
  Future<void> removeProfile(String id) async {
    final wasActive = id == activeProfileId;
    final next = await store.removeProfile(id);
    await reloadProfiles();
    if (!wasActive) return;

    api?.close();
    api = null;
    units = [];
    if (next == null) {
      _go(AppStage.onboarding);
      return;
    }
    activeProfileId = null;     // force switchProfile to do the work
    await switchProfile(next);
  }

  // --- other addresses for the active server (Nerd screen) -----------------

  /// The user's own fallback addresses, normalised, in the order to try them.
  Future<void> setFallbackUrls(List<String> raw) async {
    final urls = <String>[];
    for (final r in raw) {
      final u = ApiClient.normalizeUrl(r);
      if (u.isNotEmpty && !urls.contains(u)) urls.add(u);
    }
    await store.saveFallbackUrls(urls);
    await _refreshAlternates();
  }

  Future<void> setLanFallback(bool on) async {
    await store.setLanFallback(on);
    if (on) {
      try {
        await learnLanAddresses();
      } catch (_) {/* kept switched on; learned next time it can be */}
    }
    await _refreshAlternates();
  }

  Future<void> _refreshAlternates() async {
    api?.alternates = await store.alternateUrls;
    notifyListeners();
  }

  /// Ask the server for its own LAN address and port (`/api/system`,
  /// Breeze Core 3.0.5+) and keep them as the last tier of fallbacks.
  ///
  /// Returns why there is nothing to keep, or null when addresses were
  /// learned. A server bound only to loopback sits behind a proxy on its own
  /// machine: nothing on the LAN can reach it directly, so there is no LAN
  /// address worth trying.
  Future<String?> learnLanAddresses() async {
    final sys = await api!.systemInfo();
    final net = (sys['network'] as Map?)?.cast<String, dynamic>() ?? const {};
    final urls = lanUrlsFrom(net);
    await store.saveLanAddresses(urls);
    await _refreshAlternates();
    if (urls.isNotEmpty) return null;
    final host = net['bind_host']?.toString() ?? '';
    return _isLoopback(host)
        ? 'The server only listens on its own machine ($host), behind a proxy, '
            'so nothing on the LAN can reach it directly.'
        : 'The server did not report a LAN address.';
  }

  /// `http://ip:port` for each address the server can be reached at on its
  /// LAN, from its `/api/system` network facts.
  @visibleForTesting
  static List<String> lanUrlsFrom(Map<String, dynamic> net) {
    final host = net['bind_host']?.toString() ?? '0.0.0.0';
    final port = net['bind_port']?.toString() ?? '8420';
    if (_isLoopback(host)) return const [];
    final ips = <String>[
      // Bound to one address: that is the only one that answers.
      if (host != '0.0.0.0' && host != '::' && host.isNotEmpty) host
      else ...((net['local_addresses'] as List?) ?? const []).map((e) => '$e'),
    ];
    return [
      for (final ip in ips)
        if (ip.isNotEmpty) 'http://${ip.contains(':') ? '[$ip]' : ip}:$port',
    ];
  }

  /// Once per launch, if the LAN tier is on: the server's address can change
  /// (DHCP), and a stale one is a fallback that never answers. Best-effort.
  Future<void> _refreshLanIfOn() async {
    try {
      if (await store.lanFallback) await learnLanAddresses();
    } catch (_) {/* keep the last ones learned */}
  }

  static bool _isLoopback(String host) =>
      host == '127.0.0.1' || host == '::1' || host == 'localhost';

  /// Forget the current server and start over (Settings → Change server).
  Future<void> changeServer() async {
    final id = activeProfileId;
    if (id != null) {
      await removeProfile(id);
      return;
    }
    await store.clearAll();
    api?.close();
    api = null;
    units = [];
    error = null;
    _go(AppStage.onboarding);
  }
}
