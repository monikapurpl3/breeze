// The Nerd screen's internal settings, below the UI: the order fallback
// addresses are tried in, latency measured only when asked, the server's LAN
// addresses, the curve's path through midnight, and the cat facts.

import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:breeze/src/api_client.dart';
import 'package:breeze/src/app_controller.dart';
import 'package:breeze/src/models.dart';
import 'package:breeze/src/screens/program_edit_screen.dart';
import 'package:breeze/src/secure_store.dart';
import 'package:breeze/src/widgets/curve_painter.dart';
import 'package:breeze/src/widgets/loading_cat.dart';
import 'package:breeze/src/widgets/scene_editor.dart';

/// A server reachable only at [up]; every other host refuses the connection.
MockClient onlyAt(String up, {List<String>? log}) => MockClient((req) async {
      log?.add(req.url.host);
      if (req.url.host != up) throw http.ClientException('refused', req.url);
      return http.Response(jsonEncode({'status': 'ok'}), 200);
    });

void main() {
  group('fallback addresses', () {
    test('the order: the one in use first, then the rest, main first again after a while', () {
      expect(ApiClient.attemptOrder(1, 0), [0]);
      expect(ApiClient.attemptOrder(3, 0), [0, 1, 2]);
      expect(ApiClient.attemptOrder(3, 2), [2, 0, 1]);
      expect(ApiClient.attemptOrder(3, 2, retryMain: true), [0, 2, 1]);
    });

    test('an unreachable main address falls through to a fallback, which then sticks', () async {
      final log = <String>[];
      final api = ApiClient(
        baseUrl: 'https://main.test',
        apiKey: 'k',
        alternates: ['https://dead.test', 'http://192.168.1.98:8420'],
        client: onlyAt('192.168.1.98', log: log),
      );
      await api.health();
      expect(api.currentUrl.value, 'http://192.168.1.98:8420');
      expect(log, ['main.test', 'dead.test', '192.168.1.98']);

      log.clear();
      await api.health();
      expect(log, ['192.168.1.98'], reason: 'no timeout paid on the dead ones again');
    });

    test('a main address that stays down gets one short try per two minutes, not one per request', () async {
      final log = <String>[];
      var clock = DateTime(2026, 10, 10, 12);
      final api = ApiClient(
        baseUrl: 'https://main.test',
        apiKey: 'k',
        alternates: ['https://fb.test'],
        client: onlyAt('fb.test', log: log),
      )..now = () => clock;
      await api.health(); // main fails, fallback answers
      clock = clock.add(const Duration(minutes: 3));
      log.clear();
      await api.health();
      expect(log, ['main.test', 'fb.test'], reason: 'due: the main address is tried first');
      log.clear();
      await api.health();
      await api.health();
      expect(log, ['fb.test', 'fb.test'], reason: 'not again until two minutes have passed');
      clock = clock.add(const Duration(minutes: 3));
      log.clear();
      await api.health();
      expect(log, ['main.test', 'fb.test']);
    });

    test('an HTTP error is an answer: no fallback for a 500', () async {
      final log = <String>[];
      final api = ApiClient(
        baseUrl: 'https://main.test',
        apiKey: 'k',
        alternates: ['https://other.test'],
        client: MockClient((req) async {
          log.add(req.url.host);
          return http.Response('{"detail":"boom"}', 500);
        }),
      );
      await expectLater(api.health(), throwsA(isA<ApiException>()));
      expect(log, ['main.test']);
      expect(api.currentUrl.value, 'https://main.test');
    });

    test('nothing reachable says how many addresses were tried', () async {
      final api = ApiClient(
        baseUrl: 'https://main.test',
        apiKey: 'k',
        alternates: ['https://other.test'],
        client: onlyAt('nowhere.test'),
      );
      await expectLater(
        api.health(),
        throwsA(isA<ApiException>()
            .having((e) => e.status, 'status', 0)
            .having((e) => e.message, 'message', contains('any of its 2 addresses'))),
      );
    });

    test('setting new alternates goes back to the main address', () async {
      final api = ApiClient(
        baseUrl: 'https://main.test',
        apiKey: 'k',
        alternates: ['https://fb.test'],
        client: onlyAt('fb.test'),
      );
      await api.health();
      expect(api.currentUrl.value, 'https://fb.test');
      api.alternates = ['https://fb2.test'];
      expect(api.currentUrl.value, 'https://main.test');
    });

    test('the profile keeps them, and adds the LAN ones only when switched on', () async {
      FlutterSecureStorage.setMockInitialValues({
        'profile_index': '["s1"]',
        'active_profile': 's1',
        'p_s1_url': 'https://main.test',
        'p_s1_api_key': 'k',
      });
      final s = SecureStore();
      await s.saveFallbackUrls(['https://fb.test']);
      await s.saveLanAddresses(['http://192.168.1.98:8420']);
      expect(await s.alternateUrls, ['https://fb.test']);
      await s.setLanFallback(true);
      expect(await s.alternateUrls, ['https://fb.test', 'http://192.168.1.98:8420']);
    });
  });

  group('latency', () {
    test('measured only while the readout is switched on', () async {
      final api = ApiClient(baseUrl: 'https://main.test', apiKey: 'k', client: onlyAt('main.test'));
      await api.health();
      expect(api.latencyMs.value, isNull, reason: 'not measured by default');
      api.measureLatency = true;
      await api.health();
      expect(api.latencyMs.value, isNotNull);
      api.measureLatency = false;
      expect(api.latencyMs.value, isNull, reason: 'switching it off clears the number');
    });
  });

  group('the server\'s LAN addresses', () {
    test('every local address, at the port it listens on', () {
      expect(
        AppController.lanUrlsFrom({
          'bind_host': '0.0.0.0',
          'bind_port': '8420',
          'local_addresses': ['192.168.1.98'],
        }),
        ['http://192.168.1.98:8420'],
      );
    });

    test('bound to one address: only that one', () {
      expect(
        AppController.lanUrlsFrom({
          'bind_host': '192.168.1.5',
          'bind_port': '9000',
          'local_addresses': ['192.168.1.5', '10.0.0.2'],
        }),
        ['http://192.168.1.5:9000'],
      );
    });

    test('bound to loopback, behind a proxy: none, because nothing on the LAN reaches it', () {
      expect(
        AppController.lanUrlsFrom({
          'bind_host': '127.0.0.1',
          'bind_port': '8420',
          'local_addresses': ['192.168.1.98'],
        }),
        isEmpty,
      );
    });
  });

  group('curves', () {
    final pts = [
      CurvePoint(time: '22:00', temperature: 24.0),
      CurvePoint(time: '02:00', temperature: 26.0),
    ];

    test('run through midnight, the way the server follows them', () {
      expect(curveAt(pts, 22 * 60), 24.0);
      expect(curveAt(pts, 0), closeTo(25.0, 0.001)); // halfway, across midnight
      expect(curveAt(pts, 2 * 60), 26.0);
      expect(curveAt(pts, 12 * 60), closeTo(25.0, 0.001)); // halfway back, 02:00 to 22:00
    });

    test('one point is a flat line', () {
      expect(curveAt([CurvePoint(time: '08:00', temperature: 21.5)], 300), 21.5);
    });
  });

  group('cat facts', () {
    tearDown(() {
      CatFacts.custom = const [];
      CatFacts.includeBuiltIn = true;
    });

    test('yours, the built-in ones, or both -- never none', () {
      expect(CatFacts.pool, CatFacts.all);
      CatFacts.custom = ['Mine.'];
      expect(CatFacts.pool, ['Mine.', ...CatFacts.all]);
      CatFacts.includeBuiltIn = false;
      expect(CatFacts.pool, ['Mine.']);
      CatFacts.custom = ['  '];
      expect(CatFacts.pool, CatFacts.all, reason: 'blank lines are not facts');
    });
  });

  group('program wording', () {
    test('days in words', () {
      expect(daysLabel([]), 'Every day');
      expect(daysLabel([0, 1, 2, 3, 4, 5, 6]), 'Every day');
      expect(daysLabel([0, 1, 2, 3, 4]), 'Weekdays');
      expect(daysLabel([5, 6]), 'Weekends');
      expect(daysLabel([0, 2, 4]), 'Mon, Wed, Fri');
    });

    test('a scene in words, with the fan slider\'s names', () {
      final s = ClimateSettings(
        powerState: true,
        operationalMode: 'HEAT',
        targetTemperature: 23.5,
        fanSpeed: 40,
        swingMode: 'VERTICAL',
        eco: true,
        turbo: false,
      );
      expect(SceneSummary.describe(s, 'C'), 'heat · 23.5° · fan low · flaps vertical · eco');
      expect(SceneSummary.describe(ClimateSettings(powerState: false), 'C'), 'off');
      expect(fanWord(102), 'auto');
      expect(fanWord(100), 'max');
      expect(fanWord(20), 'silent');
    });
  });
}
