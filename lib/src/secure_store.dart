// Encrypted persistence for the connection secrets.
//
// flutter_secure_storage (v10+) encrypts values by default on Android
// (Keystore-wrapped custom ciphers), so the access key and the per-device
// credential never touch disk in the clear.
//
// Two device-credential shapes are stored, keyed by `auth_version`:
//   v1 — a bearer token (device_token)
//   v2 — an Ed25519 private-key seed (device_priv_seed) + the server's
//        key id (device_key_id). The public half lives on the server.

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class SecureStore {
  final FlutterSecureStorage _s = const FlutterSecureStorage();

  static const _kUrl = 'server_url';
  static const _kKey = 'api_key';
  static const _kToken = 'device_token';       // v1
  static const _kLabel = 'device_label';
  static const _kSeed = 'device_priv_seed';     // v2 (base64url Ed25519 seed)
  static const _kKeyId = 'device_key_id';        // v2 (server token_id)
  static const _kAuthV = 'auth_version';         // "1" | "2"

  Future<String?> get serverUrl => _s.read(key: _kUrl);
  Future<String?> get apiKey => _s.read(key: _kKey);
  Future<String?> get deviceToken => _s.read(key: _kToken);
  Future<String?> get deviceLabel => _s.read(key: _kLabel);
  Future<String?> get deviceSeed => _s.read(key: _kSeed);
  Future<String?> get deviceKeyId => _s.read(key: _kKeyId);

  Future<int> get authVersion async =>
      int.tryParse(await _s.read(key: _kAuthV) ?? '1') ?? 1;

  Future<void> saveConnection(String url, String key, String label) async {
    await _s.write(key: _kUrl, value: url);
    await _s.write(key: _kKey, value: key);
    await _s.write(key: _kLabel, value: label);
  }

  /// Persist a v1 bearer token (legacy pairing).
  Future<void> saveToken(String token) async {
    await _s.write(key: _kToken, value: token);
    await _s.write(key: _kAuthV, value: '1');
  }

  /// Persist a v2 Ed25519 credential (seed + server key id) and drop any
  /// stale v1 token so the two can't coexist.
  Future<void> saveV2(String seedB64, String keyId) async {
    await _s.write(key: _kSeed, value: seedB64);
    await _s.write(key: _kKeyId, value: keyId);
    await _s.write(key: _kAuthV, value: '2');
    await _s.delete(key: _kToken);
  }

  /// Forget the device credential (v1 and v2), keeping server URL + key so
  /// re-pairing is quick.
  Future<void> clearToken() async {
    await _s.delete(key: _kToken);
    await _s.delete(key: _kSeed);
    await _s.delete(key: _kKeyId);
    await _s.delete(key: _kAuthV);
  }

  /// Forget everything (used by "change server").
  Future<void> clearAll() => _s.deleteAll();
}
