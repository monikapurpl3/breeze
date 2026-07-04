// Encrypted persistence for the connection secrets.
//
// flutter_secure_storage (v10+) encrypts values by default on Android
// (Keystore-wrapped custom ciphers), so the access key and per-device
// token never touch disk in the clear.

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class SecureStore {
  final FlutterSecureStorage _s = const FlutterSecureStorage();

  static const _kUrl = 'server_url';
  static const _kKey = 'api_key';
  static const _kToken = 'device_token';
  static const _kLabel = 'device_label';

  Future<String?> get serverUrl => _s.read(key: _kUrl);
  Future<String?> get apiKey => _s.read(key: _kKey);
  Future<String?> get deviceToken => _s.read(key: _kToken);
  Future<String?> get deviceLabel => _s.read(key: _kLabel);

  Future<void> saveConnection(String url, String key, String label) async {
    await _s.write(key: _kUrl, value: url);
    await _s.write(key: _kKey, value: key);
    await _s.write(key: _kLabel, value: label);
  }

  Future<void> saveToken(String token) => _s.write(key: _kToken, value: token);

  /// Forget the device token (keeps server URL + key so re-pairing is quick).
  Future<void> clearToken() => _s.delete(key: _kToken);

  /// Forget everything (used by "change server").
  Future<void> clearAll() => _s.deleteAll();
}
