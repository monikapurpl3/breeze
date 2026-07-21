// Ed25519 request signing for auth-version 2 (the "v2" profile).
//
// The device credential is an Ed25519 keypair generated on-device. The
// private key never leaves the phone (stored as a 32-byte seed in
// flutter_secure_storage, i.e. Keystore-wrapped at rest); the server holds
// only the public key. Each request is signed over a canonical string that
// binds the method, path, timestamp, a per-request nonce, and a SHA3-512
// digest of the body:
//
//   breeze-auth-v2\n{METHOD}\n{path}\n{timestamp}\n{nonce}\n{sha3_512(body) hex}
//
// This is the exact construction meow_ac/security/signing.py verifies — the
// two are cross-checked in the server's tests/. SHA3-512 comes from
// pointycastle (FIPS-202, verified byte-equal to Python's hashlib.sha3_512);
// Ed25519 from the `cryptography` package (PureEdDSA / RFC 8032).

import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:pointycastle/digests/sha3.dart';

String _b64u(List<int> bytes) => base64Url.encode(bytes).replaceAll('=', '');

Uint8List _b64uDecode(String s) {
  final pad = (4 - s.length % 4) % 4;
  return base64Url.decode(s + '=' * pad);
}

String _hex(List<int> bytes) =>
    bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

class DeviceSigner {
  static final Ed25519 _algo = Ed25519();
  static final Random _rnd = Random.secure();

  final SimpleKeyPair _keyPair;

  /// The server's identifier for this device (its token_id), sent in the
  /// clear as X-Breeze-Key-Id. Empty until enrollment/upgrade returns it.
  final String keyId;

  DeviceSigner._(this._keyPair, this.keyId);

  /// A brand-new keypair (used at enrollment and at v1→v2 upgrade).
  static Future<DeviceSigner> generate() async =>
      DeviceSigner._(await _algo.newKeyPair(), '');

  /// Restore a keypair from its stored 32-byte seed and known key id.
  static Future<DeviceSigner> fromSeed(String seedB64, String keyId) async =>
      DeviceSigner._(await _algo.newKeyPairFromSeed(_b64uDecode(seedB64)), keyId);

  /// Same key material, now bound to the key id the server assigned.
  DeviceSigner withKeyId(String id) => DeviceSigner._(_keyPair, id);

  /// The public key (raw 32 bytes, base64url no padding) to register.
  Future<String> publicKeyB64() async =>
      _b64u((await _keyPair.extractPublicKey()).bytes);

  /// The private seed (base64url) for at-rest storage in SecureStore.
  Future<String> seedB64() async =>
      _b64u(await _keyPair.extractPrivateKeyBytes());

  static Uint8List sha3_512(List<int> data) =>
      SHA3Digest(512).process(Uint8List.fromList(data));

  /// Build the X-Breeze-* signature headers for one request. `path` is the
  /// request path (with query string, if any) exactly as the server sees it.
  Future<Map<String, String>> signHeaders(
      String method, String path, List<int> body) async {
    final ts = (DateTime.now().millisecondsSinceEpoch ~/ 1000).toString();
    final nonce =
        _b64u(List<int>.generate(16, (_) => _rnd.nextInt(256)));
    final bodyHash = _hex(sha3_512(body));
    final canonical = utf8.encode(
        ['breeze-auth-v2', method.toUpperCase(), path, ts, nonce, bodyHash]
            .join('\n'));
    final sig = await _algo.sign(canonical, keyPair: _keyPair);
    return {
      'X-Breeze-Auth-Version': '2',
      'X-Breeze-Key-Id': keyId,
      'X-Breeze-Timestamp': ts,
      'X-Breeze-Nonce': nonce,
      'X-Breeze-Signature': _b64u(sig.bytes),
    };
  }
}
