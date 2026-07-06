// The single HTTP layer. Every request carries the access key and (once
// paired) the per-device bearer token. TLS is required except for private
// LAN addresses; timeouts are enforced; non-2xx becomes a typed error.

import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'models.dart';

class ApiException implements Exception {
  final int status; // 0 = network/transport error
  final String message;
  ApiException(this.status, this.message);
  bool get unauthorized => status == 401;
  @override
  String toString() => message;
}

class ApiClient {
  final String baseUrl; // normalized, no trailing slash
  final String apiKey;
  String? deviceToken;
  final Duration timeout;
  final http.Client _http;

  ApiClient({
    required this.baseUrl,
    required this.apiKey,
    this.deviceToken,
    http.Client? client,
    this.timeout = const Duration(seconds: 15),
  }) : _http = client ?? http.Client();

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

  Map<String, String> _headers({bool withToken = true, bool json = false}) {
    final h = <String, String>{'X-API-Key': apiKey};
    if (withToken && deviceToken != null) h['Authorization'] = 'Bearer $deviceToken';
    if (json) h['Content-Type'] = 'application/json';
    return h;
  }

  Uri _uri(String path) => Uri.parse('$baseUrl$path');

  Future<dynamic> _send(
    String method,
    String path, {
    Object? body,
    bool withToken = true,
  }) async {
    late http.Response r;
    try {
      final headers = _headers(withToken: withToken, json: body != null);
      final uri = _uri(path);
      final encoded = body == null ? null : jsonEncode(body);
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
  Future<Map<String, dynamic>> enrollStart(String label) async =>
      (await _send('POST', '/api/auth/enroll/start',
          body: {'label': label}, withToken: false)) as Map<String, dynamic>;

  Future<Map<String, dynamic>> enrollPoll(String sessionId) async =>
      (await _send('POST', '/api/auth/enroll/poll',
          body: {'session_id': sessionId}, withToken: false)) as Map<String, dynamic>;

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
