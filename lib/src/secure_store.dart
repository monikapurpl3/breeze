// Encrypted persistence for the connection secrets, one set per server.
//
// flutter_secure_storage (v10+) encrypts values by default on Android
// (Keystore-wrapped custom ciphers), so access keys and per-device
// credentials never touch disk in the clear.
//
// **Profiles.** Every secret is namespaced by a profile id (`p_<id>_<field>`)
// and one key, `active_profile`, says which is current. Switching servers is
// therefore just moving that pointer: each server keeps its own credential, so
// returning to one you've used before needs no re-pairing — which matters
// because approving a pairing requires an admin on *that* server's LAN, i.e.
// physically being on the other network.
//
// Two device-credential shapes are stored per profile, keyed by `auth_version`:
//   v1 — a bearer token (token)
//   v2 — an Ed25519 private-key seed (seed) + the server's key id (key_id).
//        The public half lives on the server.
//
// The pre-2.2.5 layout used unprefixed keys for a single server. `migrate()`
// lifts those into profile "default" once, on first launch after the update.

import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// One saved server: where it is, how we authenticate to it, what to call it.
class ServerProfile {
  const ServerProfile({
    required this.id,
    required this.name,
    required this.url,
    required this.apiKey,
    required this.label,
    this.authVersion = 1,
    this.hasCredential = false,
  });

  final String id;
  final String name;      // what the user sees; defaults to the host
  final String url;
  final String apiKey;
  final String label;     // this device's name on that server
  final int authVersion;
  final bool hasCredential;

  /// Host[:port] — the default display name, and what makes two servers
  /// distinguishable at a glance in a list.
  static String nameFor(String url) {
    final u = Uri.tryParse(url);
    if (u == null || u.host.isEmpty) return url;
    return u.hasPort ? '${u.host}:${u.port}' : u.host;
  }
}

class SecureStore {
  final FlutterSecureStorage _s = const FlutterSecureStorage();

  static const _kActive = 'active_profile';
  static const _kIndex = 'profile_index';   // JSON list of ids

  // Legacy (pre-2.2.5) single-server keys, read once by migrate().
  static const _legacyUrl = 'server_url';
  static const _legacyKey = 'api_key';
  static const _legacyToken = 'device_token';
  static const _legacyLabel = 'device_label';
  static const _legacySeed = 'device_priv_seed';
  static const _legacyKeyId = 'device_key_id';
  static const _legacyAuthV = 'auth_version';

  String? _active;

  String _k(String id, String field) => 'p_${id}_$field';

  // --- profile bookkeeping --------------------------------------------------

  Future<List<String>> _ids() async {
    final raw = await _s.read(key: _kIndex);
    if (raw == null || raw.isEmpty) return <String>[];
    try {
      return (jsonDecode(raw) as List).cast<String>();
    } catch (_) {
      return <String>[];
    }
  }

  Future<void> _writeIds(List<String> ids) =>
      _s.write(key: _kIndex, value: jsonEncode(ids));

  Future<String?> get activeProfileId async =>
      _active ??= await _s.read(key: _kActive);

  Future<void> setActiveProfile(String id) async {
    _active = id;
    await _s.write(key: _kActive, value: id);
  }

  /// Every saved server, in the order they were added.
  Future<List<ServerProfile>> profiles() async {
    final out = <ServerProfile>[];
    for (final id in await _ids()) {
      final url = await _s.read(key: _k(id, 'url'));
      final key = await _s.read(key: _k(id, 'api_key'));
      if (url == null || key == null) continue;   // half-written: skip, not crash
      final av = int.tryParse(await _s.read(key: _k(id, 'auth_version')) ?? '1') ?? 1;
      final hasCred = av >= 2
          ? (await _s.read(key: _k(id, 'seed'))) != null
          : (await _s.read(key: _k(id, 'token'))) != null;
      out.add(ServerProfile(
        id: id,
        name: await _s.read(key: _k(id, 'name')) ?? ServerProfile.nameFor(url),
        url: url,
        apiKey: key,
        label: await _s.read(key: _k(id, 'label')) ?? 'Breeze',
        authVersion: av,
        hasCredential: hasCred,
      ));
    }
    return out;
  }

  /// Create (or reuse) a profile and make it current. Returns its id.
  Future<String> createProfile({
    required String url,
    required String apiKey,
    required String label,
    String? name,
    String? id,
  }) async {
    // The same URL twice is a mistake, not a second server: reuse the existing
    // profile so a credential isn't orphaned behind a duplicate row.
    final existing = (await profiles()).where((p) => p.url == url).toList();
    final pid = id ?? (existing.isNotEmpty ? existing.first.id : _newId());

    await _s.write(key: _k(pid, 'url'), value: url);
    await _s.write(key: _k(pid, 'api_key'), value: apiKey);
    await _s.write(key: _k(pid, 'label'), value: label);
    await _s.write(key: _k(pid, 'name'), value: name ?? ServerProfile.nameFor(url));

    final ids = await _ids();
    if (!ids.contains(pid)) {
      ids.add(pid);
      await _writeIds(ids);
    }
    await setActiveProfile(pid);
    return pid;
  }

  Future<void> renameProfile(String id, String name) =>
      _s.write(key: _k(id, 'name'), value: name);

  /// Forget one server entirely. Returns the id now active, or null if that
  /// was the last one.
  Future<String?> removeProfile(String id) async {
    for (final f in ['url', 'api_key', 'label', 'name', 'token', 'seed',
                     'key_id', 'auth_version']) {
      await _s.delete(key: _k(id, f));
    }
    final ids = (await _ids())..remove(id);
    await _writeIds(ids);
    if (await activeProfileId == id) {
      if (ids.isEmpty) {
        _active = null;
        await _s.delete(key: _kActive);
        return null;
      }
      await setActiveProfile(ids.first);
    }
    return _active;
  }

  // --- the active profile's secrets ----------------------------------------
  //
  // These keep the names the rest of the app already uses, so switching
  // servers stays invisible to ApiClient and AppController.

  Future<String?> _read(String field) async {
    final id = await activeProfileId;
    return id == null ? null : _s.read(key: _k(id, field));
  }

  Future<void> _write(String field, String value) async {
    final id = await activeProfileId;
    if (id != null) await _s.write(key: _k(id, field), value: value);
  }

  Future<void> _delete(String field) async {
    final id = await activeProfileId;
    if (id != null) await _s.delete(key: _k(id, field));
  }

  Future<String?> get serverUrl => _read('url');
  Future<String?> get apiKey => _read('api_key');
  Future<String?> get deviceToken => _read('token');
  Future<String?> get deviceLabel => _read('label');
  Future<String?> get deviceSeed => _read('seed');
  Future<String?> get deviceKeyId => _read('key_id');

  Future<int> get authVersion async =>
      int.tryParse(await _read('auth_version') ?? '1') ?? 1;

  /// Point at a server, creating its profile if new. Replaces the old
  /// single-slot save; callers don't need to know about profiles.
  Future<void> saveConnection(String url, String key, String label) =>
      createProfile(url: url, apiKey: key, label: label);

  /// Persist a v1 bearer token (legacy pairing).
  Future<void> saveToken(String token) async {
    await _write('token', token);
    await _write('auth_version', '1');
  }

  /// Persist a v2 Ed25519 credential (seed + server key id) and drop any
  /// stale v1 token so the two can't coexist.
  Future<void> saveV2(String seedB64, String keyId) async {
    await _write('seed', seedB64);
    await _write('key_id', keyId);
    await _write('auth_version', '2');
    await _delete('token');
  }

  /// Forget the device credential for the active server, keeping its URL +
  /// key so re-pairing is quick.
  Future<void> clearToken() async {
    await _delete('token');
    await _delete('seed');
    await _delete('key_id');
    await _delete('auth_version');
  }

  /// Forget the active server entirely (the old "change server").
  Future<void> clearAll() async {
    final id = await activeProfileId;
    if (id != null) await removeProfile(id);
  }

  // --- migration ------------------------------------------------------------

  /// Lift a pre-2.2.5 single-server install into profile form. Idempotent:
  /// once an index exists this does nothing, and the legacy keys are deleted
  /// only after the new ones are written, so an interrupted migration retries
  /// cleanly next launch rather than losing the credential.
  Future<void> migrate() async {
    if ((await _ids()).isNotEmpty) return;
    final url = await _s.read(key: _legacyUrl);
    final key = await _s.read(key: _legacyKey);
    if (url == null || key == null) return;

    const id = 'default';
    await _s.write(key: _k(id, 'url'), value: url);
    await _s.write(key: _k(id, 'api_key'), value: key);
    await _s.write(key: _k(id, 'name'), value: ServerProfile.nameFor(url));
    final label = await _s.read(key: _legacyLabel);
    if (label != null) await _s.write(key: _k(id, 'label'), value: label);
    final token = await _s.read(key: _legacyToken);
    if (token != null) await _s.write(key: _k(id, 'token'), value: token);
    final seed = await _s.read(key: _legacySeed);
    if (seed != null) await _s.write(key: _k(id, 'seed'), value: seed);
    final keyId = await _s.read(key: _legacyKeyId);
    if (keyId != null) await _s.write(key: _k(id, 'key_id'), value: keyId);
    final av = await _s.read(key: _legacyAuthV);
    if (av != null) await _s.write(key: _k(id, 'auth_version'), value: av);

    await _writeIds([id]);
    await setActiveProfile(id);

    for (final k in [_legacyUrl, _legacyKey, _legacyToken, _legacyLabel,
                     _legacySeed, _legacyKeyId, _legacyAuthV]) {
      await _s.delete(key: k);
    }
  }

  /// Ids are opaque; time-based is enough here (profiles are created by hand,
  /// seconds apart at the fastest) and avoids pulling in a uuid package.
  String _newId() => 's${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}';
}
