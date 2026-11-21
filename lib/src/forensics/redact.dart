// What the forensic build never writes down: credentials. A value that must
// not appear is replaced by its length and the first eight hex digits of its
// SHA-256, so two logs (or a log and a server's) can still be compared --
// "the same key as yesterday?" -- without the value itself.

import 'dart:convert';

import 'package:cryptography/dart.dart';

String fingerprint(String value) {
  final digest = const DartSha256().hashSync(utf8.encode(value)).bytes;
  final hex = digest.take(4).map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  return '<redacted len=${value.length} sha=$hex>';
}

/// Header names whose values are credentials.
const _secretHeaders = {
  'x-api-key',
  'authorization',
  'x-breeze-signature',
  'cookie',
  'set-cookie',
  'proxy-authorization',
};

/// JSON fields and query parameters that hold credentials. Matched whole,
/// lower-cased; `key_id`, `token_id` and `public_key` are identifiers, not
/// secrets, and stay.
const _secretFields = {
  'api_key',
  'apikey',
  'key',
  'token',
  'device_token',
  'access_token',
  'refresh_token',
  'password',
  'secret',
  'seed',
  'private_key',
  'signature',
  'code',
  'pairing_code',
  'login_key',
};

bool isSecretHeader(String name) => _secretHeaders.contains(name.toLowerCase());

bool isSecretField(String name) => _secretFields.contains(name.toLowerCase());

Map<String, String> redactHeaders(Map<String, String> headers) => {
      for (final e in headers.entries) e.key: isSecretHeader(e.key) ? fingerprint(e.value) : e.value,
    };

/// A URL with any secret query parameter replaced.
String redactUrl(String url) {
  final u = Uri.tryParse(url);
  if (u == null || u.queryParameters.isEmpty) return url;
  if (!u.queryParameters.keys.any(isSecretField)) return url;
  return u.replace(queryParameters: {
    for (final e in u.queryParameters.entries) e.key: isSecretField(e.key) ? fingerprint(e.value) : e.value,
  }).toString();
}

Object? _redactJson(Object? v) {
  if (v is Map) {
    return {
      for (final e in v.entries)
        '${e.key}': isSecretField('${e.key}') && e.value != null && e.value is! Map && e.value is! List
            ? fingerprint('${e.value}')
            : _redactJson(e.value),
    };
  }
  if (v is List) return [for (final x in v) _redactJson(x)];
  return v;
}

/// Long runs that look like keys or tokens (hex, base64url): 32 characters
/// and up. Not across a slash, so file paths stay readable, and never a
/// UUID, which is an identifier.
final _longSecretish = RegExp(r'[A-Za-z0-9+_\-]{32,}={0,2}');
final _uuid = RegExp(r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$');

/// Text from outside -- a body, an error message: JSON has its secret
/// fields replaced; anything else has long key-like runs replaced. The
/// app's own messages (paths, fingerprints it computed) do not go through
/// this.
String redactText(String text) {
  final t = text.trimLeft();
  if (t.startsWith('{') || t.startsWith('[')) {
    try {
      return jsonEncode(_redactJson(jsonDecode(t)));
    } catch (_) {
      // Not JSON after all: fall through.
    }
  }
  return text.replaceAllMapped(_longSecretish, (m) {
    final s = m.group(0)!;
    return _uuid.hasMatch(s) ? s : fingerprint(s);
  });
}
