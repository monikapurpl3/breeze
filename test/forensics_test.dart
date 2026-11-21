// The forensic build's promises: credentials never written anywhere, the
// app's HTTP unchanged by being recorded, failures explained, and a snapshot
// that tells everything but the secrets.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:breeze/src/app_controller.dart';
import 'package:breeze/src/forensics/forensics.dart';
import 'package:breeze/src/forensics/http_log.dart';
import 'package:breeze/src/forensics/probes.dart';
import 'package:breeze/src/forensics/redact.dart';
import 'package:breeze/src/forensics/snapshot.dart';
import 'package:breeze/src/secure_store.dart';

const apiKey = 'Zx9-AbCdEfGhIjKlMnOpQrStUvWxYz012345';
const token = 'tok_1234567890abcdefghijklmnopqrstuvwxyz';
const seed = 'c2VlZHNlZWRzZWVkc2VlZHNlZWRzZWVkc2VlZHNlZWQ=';

class _RealHttp extends HttpOverrides {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('redaction', () {
    test('credential headers are fingerprinted, the rest kept', () {
      final h = redactHeaders({'X-API-Key': apiKey, 'Authorization': 'Bearer $token', 'X-Breeze-Key-Id': 'k1', 'Accept': 'application/json'});
      expect(h['X-API-Key'], startsWith('<redacted len=${apiKey.length} sha='));
      expect(h['Authorization'], startsWith('<redacted'));
      expect(h['X-Breeze-Key-Id'], 'k1');
      expect(h['Accept'], 'application/json');
      expect(h.values.join(), isNot(contains(apiKey)));
    });

    test('secret JSON fields go, at any depth and of any type; identifiers stay', () {
      final out = redactText(jsonEncode({
        'device': {'token': token, 'token_id': 'abc', 'key_id': 'kid', 'public_key': 'pub'},
        'code': 123456,
        'list': [
          {'api_key': apiKey}
        ],
        'name': 'Living room',
      }));
      expect(out, isNot(contains(token)));
      expect(out, isNot(contains(apiKey)));
      expect(out, isNot(contains('123456')));
      expect(out, contains('"token_id":"abc"'));
      expect(out, contains('"key_id":"kid"'));
      expect(out, contains('"public_key":"pub"'));
      expect(out, contains('Living room'));
    });

    test('free text: long key-like runs go; paths and UUIDs stay', () {
      const path = '/var/mobile/Containers/Data/Application/1F3AB2C4-5D6E-4F70-8A9B-0C1D2E3F4A5B/Documents/forensics';
      final out = redactText('failed with $token at $path');
      expect(out, isNot(contains(token)));
      expect(out, contains(path));
    });

    test('secret query parameters are fingerprinted', () {
      final out = redactUrl('https://h.example/api/x?key=$apiKey&unit=3');
      expect(out, isNot(contains(apiKey)));
      expect(out, contains('unit=3'));
    });

    test('a fingerprint is stable, and differs between values', () {
      expect(fingerprint('a'), fingerprint('a'));
      expect(fingerprint('a'), isNot(fingerprint('b')));
    });
  });

  group('the HTTP recorder', () {
    test('passes the response through unchanged and records it redacted', () async {
      final body = jsonEncode({'device_token': token, 'ok': true});
      final c = ForensicHttpClient(MockClient((req) async => http.Response(body, 200, headers: {'content-type': 'application/json'})));
      final r = await c.post(Uri.parse('https://h.example/api/pair'), headers: {'X-API-Key': apiKey}, body: jsonEncode({'label': 'phone'}));
      expect(r.body, body, reason: 'the app sees the real body');
      final e = HttpRecorder.I.exchanges.last;
      expect(e.status, 200);
      expect(e.requestHeaders['X-API-Key'], startsWith('<redacted'));
      expect(e.detail, isNot(contains(token)));
      expect(e.detail, isNot(contains(apiKey)));
      expect(e.detail, contains('"ok":true'));
      expect(e.ms, isNotNull);
    });

    test('a failure is recorded with what it means, and still thrown', () async {
      final c = ForensicHttpClient(MockClient((req) async =>
          throw const SocketException('Connection failed', osError: OSError('No route to host', 65))));
      await expectLater(c.get(Uri.parse('http://192.168.1.10:8420/api/units')), throwsA(isA<SocketException>()));
      final e = HttpRecorder.I.exchanges.last;
      expect(e.error, contains('Local Network'));
    });

    test('an event stream is passed on live and counted', () async {
      final ctl = StreamController<List<int>>();
      final c = ForensicHttpClient(MockClient.streaming((req, _) async =>
          http.StreamedResponse(ctl.stream, 200, headers: {'content-type': 'text/event-stream'})));
      final r = await c.send(http.Request('GET', Uri.parse('https://h.example/api/stream')));
      // Read from before the first chunk: the stream is live, not buffered.
      final all = r.stream.transform(utf8.decoder).join();
      ctl.add(utf8.encode('data: one\n\n'));
      ctl.add(utf8.encode('data: two\n\n'));
      await ctl.close();
      expect(await all, 'data: one\n\ndata: two\n\n');
      final e = HttpRecorder.I.exchanges.last;
      expect(e.streaming, isTrue);
      expect(e.chunks, 2);
    });
  });

  group('the probes', () {
    test('an open port, a closed one, and the health route', () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((req) {
        req.response
          ..headers.set('server', 'probe-test')
          ..write('{"status":"ok"}')
          ..close();
      });
      final closed = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      final closedPort = closed.port;
      await closed.close();

      // The test binding answers every HttpClient with 400; the probe needs
      // the real one.
      final lines = <String>[];
      await HttpOverrides.runWithHttpOverrides(() => probe('http://127.0.0.1:${server.port}', lines.add), _RealHttp());
      expect(lines.join('\n'), contains('(loopback)'));
      expect(lines.join('\n'), contains('TCP 127.0.0.1:${server.port}: connected'));
      expect(lines.join('\n'), contains('HTTP GET /api/health: 200'));
      expect(lines.join('\n'), contains('probe-test'));

      lines.clear();
      await HttpOverrides.runWithHttpOverrides(() => probe('http://127.0.0.1:$closedPort', lines.add), _RealHttp());
      expect(lines.join('\n'), contains('FAILED'));
      expect(lines.join('\n'), contains('refused'));
      await server.close(force: true);
    });

    test('errno 65 is read as the local network permission', () {
      expect(explainOsError(65), contains('Local Network'));
      expect(explainOsError(61), contains('refused'));
    });
  });

  group('the snapshot', () {
    test('says what the keychain holds, never the values', () async {
      SharedPreferences.setMockInitialValues({'pref_theme_mode': 'dark'});
      FlutterSecureStorage.setMockInitialValues({
        'profile_index': '["s1"]',
        'active_profile': 's1',
        'p_s1_url': 'https://breeze.example.com',
        'p_s1_api_key': apiKey,
        'p_s1_token': token,
        'p_s1_seed': seed,
        'p_s1_label': 'Sirocco-4820937',
      });
      final c = AppController(SecureStore());
      Forensics.I.log('test', 'a line in the log');
      final s = await snapshot(c);
      expect(s, contains('### Keychain, as the app reads it'));
      expect(s, contains('p_s1_api_key: <redacted len=${apiKey.length}'));
      expect(s, contains('p_s1_seed: <redacted'));
      expect(s, contains('pref_theme_mode = dark'));
      for (final secret in [apiKey, token, seed]) {
        expect(s, isNot(contains(secret)), reason: 'a secret in the snapshot');
      }
    });
  });
}
