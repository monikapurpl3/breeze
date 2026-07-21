// The single HTTP layer. Every request carries the access key and (once
// paired) the per-device bearer token. TLS is required except for private
// LAN addresses; timeouts are enforced; non-2xx becomes a typed error.

import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'device_signer.dart';
import 'models.dart';
import 'secure_store.dart';

class ApiException implements Exception {
  final int status; // 0 = network/transport error
  final String message;
  ApiException(this.status, this.message);
  bool get unauthorized => status == 401;
  // 426 Upgrade Required — the server refuses this device's (outdated) auth
  // version. The app resolves this by upgrading its credential to v2.
  bool get upgradeRequired => status == 426;
  @override
  String toString() => message;
}

class ApiClient {
  final String baseUrl; // normalized, no trailing slash
  final String apiKey;
  // v1 credential (bearer). Null once the device is on v2.
  String? deviceToken;
  // v2 credential (Ed25519 request signer). Null on a v1 device.
  DeviceSigner? signer;
  // Which auth profile this client sends: 1 = bearer, 2 = signed requests.
  int authVersion;
  final Duration timeout;
  final http.Client _http;

  ApiClient({
    required this.baseUrl,
    required this.apiKey,
    this.deviceToken,
    this.signer,
    this.authVersion = 1,
    http.Client? client,
    this.timeout = const Duration(seconds: 15),
  }) : _http = client ?? http.Client();

  /// Build a client from stored credentials, or null if server+key are
  /// missing. Used by the foreground app and the headless widget isolate so
  /// request signing is set up identically everywhere. A returned client may
  /// still lack a device credential (only URL+key stored) — check
  /// [hasDeviceCredential] before hitting authenticated routes.
  static Future<ApiClient?> fromStore(SecureStore store) async {
    final url = await store.serverUrl;
    final key = await store.apiKey;
    if (url == null || key == null) return null;
    if (await store.authVersion >= 2) {
      final seed = await store.deviceSeed;
      final keyId = await store.deviceKeyId;
      if (seed != null && keyId != null) {
        return ApiClient(
          baseUrl: url,
          apiKey: key,
          signer: await DeviceSigner.fromSeed(seed, keyId),
          authVersion: 2,
        );
      }
    }
    return ApiClient(
      baseUrl: url, apiKey: key, deviceToken: await store.deviceToken, authVersion: 1,
    );
  }

  bool get hasDeviceCredential => deviceToken != null || signer != null;

  /// Switch this live client to v2, dropping the bearer token. Called after a
  /// successful enrollment or in-place upgrade.
  void adoptSigner(DeviceSigner s) {
    signer = s;
    authVersion = 2;
    deviceToken = null;
  }

  /// Normalize user input into a base URL. Defaults to https; only allows
  /// http:// for private/loopback hosts (and Android blocks cleartext
  /// anyway unless explicitly opted in), so public servers are TLS-only.
  static String normalizeUrl(String raw) {
    var s = raw.trim();
    if (s.isEmpty) return s;
    if (!s.contains('://')) s = 'https://$s';
    final u = Uri.parse(s);
    if (u.scheme == 'http' && !_isPrivateHost(u.host)) {
      s = s.replaceFirst('http://', 'https://');
    }
    return s.replaceAll(RegExp(r'/+$'), '');
  }

  static bool _isPrivateHost(String host) {
    if (host == 'localhost') return true;
    final m = RegExp(r'^(\d+)\.(\d+)\.(\d+)\.(\d+)$').firstMatch(host);
    if (m == null) return false;
    final a = int.parse(m.group(1)!), b = int.parse(m.group(2)!);
    return a == 10 ||
        a == 127 ||
        (a == 192 && b == 168) ||
        (a == 172 && b >= 16 && b <= 31);
  }

  Map<String, String> _headers({bool json = false}) {
    final h = <String, String>{'X-API-Key': apiKey};
    if (json) h['Content-Type'] = 'application/json';
    return h;
  }

  Uri _uri(String path) => Uri.parse('$baseUrl$path');

  /// Attach the device credential. v1 adds the bearer header; v2 signs the
  /// request (over the path + exact body bytes) via [DeviceSigner]. The
  /// `path` signed is the leading-slash request path — exactly what the
  /// server reconstructs from request.url.path.
  Future<void> _authenticate(
    Map<String, String> headers,
    String method,
    String path,
    List<int> bodyBytes,
  ) async {
    if (authVersion >= 2 && signer != null) {
      headers.addAll(await signer!.signHeaders(method, path, bodyBytes));
    } else if (deviceToken != null) {
      headers['Authorization'] = 'Bearer $deviceToken';
    }
  }

  Future<dynamic> _send(
    String method,
    String path, {
    Object? body,
    bool withToken = true,
  }) async {
    late http.Response r;
    try {
      final headers = _headers(json: body != null);
      final uri = _uri(path);
      final encoded = body == null ? null : jsonEncode(body);
      if (withToken) {
        await _authenticate(
          headers, method, path, encoded == null ? const [] : utf8.encode(encoded));
      }
      switch (method) {
        case 'GET':
          r = await _http.get(uri, headers: headers).timeout(timeout);
          break;
        case 'POST':
          r = await _http.post(uri, headers: headers, body: encoded).timeout(timeout);
          break;
        case 'PUT':
          r = await _http.put(uri, headers: headers, body: encoded).timeout(timeout);
          break;
        case 'PATCH':
          r = await _http.patch(uri, headers: headers, body: encoded).timeout(timeout);
          break;
        case 'DELETE':
          r = await _http.delete(uri, headers: headers, body: encoded).timeout(timeout);
          break;
        default:
          throw ApiException(0, 'unsupported method $method');
      }
    } on TimeoutException {
      throw ApiException(0, 'timed out reaching the server');
    } catch (e) {
      throw ApiException(0, 'network error: $e');
    }

    if (r.statusCode >= 200 && r.statusCode < 300) {
      if (r.body.isEmpty) return null;
      return jsonDecode(r.body);
    }
    throw ApiException(r.statusCode, _errorText(r));
  }

  String _errorText(http.Response r) {
    try {
      final j = jsonDecode(r.body);
      if (j is Map && j['detail'] != null) return j['detail'].toString();
    } catch (_) {}
    switch (r.statusCode) {
      case 401:
        return 'not authorised — pairing required';
      case 403:
        return 'forbidden (admin action must come from the LAN)';
      case 404:
        return 'not found';
      case 429:
        return 'rate limited — slow down';
      default:
        return 'server error (${r.statusCode})';
    }
  }

  // --- enrollment (needs only the access key) ---
  /// Begin enrollment. When [publicKey] is given the device enrolls as
  /// auth-version 2 (Ed25519); the server stores only that public key and no
  /// secret is ever returned. Omit it for legacy v1 bearer enrollment.
  Future<Map<String, dynamic>> enrollStart(String label, {String? publicKey}) async {
    final body = <String, dynamic>{'label': label};
    if (publicKey != null) {
      body['auth_version'] = 2;
      body['public_key'] = publicKey;
    }
    return (await _send('POST', '/api/auth/enroll/start', body: body, withToken: false))
        as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> enrollPoll(String sessionId) async =>
      (await _send('POST', '/api/auth/enroll/poll',
          body: {'session_id': sessionId}, withToken: false)) as Map<String, dynamic>;

  /// Migrate this already-enrolled device from v1 (bearer) to v2 (Ed25519)
  /// in place. Sent with the *current* v1 credential; the server keeps the
  /// same token_id and returns {token_id, auth_version:2}. No re-pairing.
  Future<Map<String, dynamic>> upgradeToV2(String publicKey) async =>
      (await _send('POST', '/api/auth/upgrade',
          body: {'public_key': publicKey})) as Map<String, dynamic>;

  // --- units ---
  Future<List<UnitSummary>> listUnits() async {
    final j = await _send('GET', '/api/units') as List;
    return j.map((e) => UnitSummary.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<UnitState> getState(String id) async =>
      UnitState.fromJson(await _send('GET', '/api/units/$id/state') as Map<String, dynamic>);

  /// All units' states in one call (Breeze Core >= 2.4.0). Throws
  /// ApiException(404) on older servers — callers fall back to per-unit.
  Future<BatchStates> listStates() async =>
      BatchStates.fromJson(await _send('GET', '/api/units/state') as Map<String, dynamic>);

  /// Server metadata for feature-detection (Breeze Core >= 2.4.0):
  /// {name, version, features[], units}. Needs only the API key.
  Future<Map<String, dynamic>> serverInfo() async =>
      (await _send('GET', '/api/version', withToken: false)) as Map<String, dynamic>;

  /// Remove a unit from the server's config (Breeze Core >= 2.4.0).
  Future<void> deleteUnit(String id) => _send('DELETE', '/api/units/$id');

  Future<UnitState> control(String id, ClimateSettings s) async => UnitState.fromJson(
      await _send('POST', '/api/units/$id/control', body: s.toJson()) as Map<String, dynamic>);

  /// Rename a unit (server persists it to config.json).
  Future<void> renameUnit(String id, String name) =>
      _send('PATCH', '/api/units/$id', body: {'name': name});

  /// Add a unit by its LAN IP — the server discovers it and writes config.
  /// Returns the created unit view {id, name, ip, port, has_v3_credentials}.
  Future<Map<String, dynamic>> addUnitByIp(String ip, String? name) async =>
      (await _send('POST', '/api/units', body: {
        'ip': ip,
        if (name != null && name.trim().isNotEmpty) 'name': name.trim(),
      })) as Map<String, dynamic>;

  // --- programs ---
  Future<List<Program>> listPrograms() async {
    final j = await _send('GET', '/api/programs') as List;
    return j.map((e) => Program.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<Program> createProgram(Program p) async => Program.fromJson(
      await _send('POST', '/api/programs', body: p.toSpecJson()) as Map<String, dynamic>);

  Future<Program> updateProgram(Program p) async => Program.fromJson(
      await _send('PUT', '/api/programs/${p.id}', body: p.toSpecJson()) as Map<String, dynamic>);

  Future<void> deleteProgram(String id) => _send('DELETE', '/api/programs/$id');

  Future<void> applyProgram(String id) => _send('POST', '/api/programs/$id/apply');

  Future<Map<String, dynamic>> schedulerStatus() async =>
      (await _send('GET', '/api/programs/status')) as Map<String, dynamic>;

  void close() => _http.close();
}
