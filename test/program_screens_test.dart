// The program screens and the Nerd screen's Internal tab, on a phone the size
// of a Galaxy S25+ (1440 x 3120 at 3.75, so 384 x 832): nothing overflows, the
// kind names never break across lines -- they used to, a last letter on a
// line of its own -- and every control can be reached and named.

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:breeze/src/api_client.dart';
import 'package:breeze/src/app_controller.dart';
import 'package:breeze/src/app_scope.dart';
import 'package:breeze/src/models.dart';
import 'package:breeze/src/screens/internal_tab.dart';
import 'package:breeze/src/screens/program_edit_screen.dart';
import 'package:breeze/src/screens/programs_screen.dart';
import 'package:breeze/src/secure_store.dart';

final _units = [
  UnitSummary(id: '1', name: 'Living room', ip: '192.168.1.41'),
  UnitSummary(id: '2', name: 'Bedroom', ip: '192.168.1.42'),
];

final _scene = {
  'power_state': true,
  'operational_mode': 'HEAT',
  'target_temperature': 22.0,
  'fan_speed': 102,
  'swing_mode': 'OFF',
  'eco': false,
  'turbo': false,
};

final _programs = <Map<String, dynamic>>[
  {'id': 'f', 'name': 'Cosy evening', 'enabled': true, 'unit_ids': ['1'], 'kind': 'favourite',
    'favourite': _scene, 'schedule': [], 'curve': null},
  {'id': 's', 'name': 'Weekday mornings', 'enabled': true, 'unit_ids': [], 'kind': 'schedule',
    'favourite': null, 'curve': null, 'schedule': [
      {'days': [0, 1, 2, 3, 4], 'time': '06:30', 'settings': _scene},
      {'days': [5, 6], 'time': '09:00', 'settings': {..._scene, 'power_state': false}},
    ]},
  {'id': 'c', 'name': 'Summer nights', 'enabled': false, 'unit_ids': ['2'], 'kind': 'curve',
    'favourite': null, 'schedule': [], 'curve': {'operational_mode': 'COOL', 'fan_speed': 20,
      'points': [{'time': '22:00', 'temperature': 24.0}, {'time': '06:00', 'temperature': 26.0}]}},
];

Future<AppController> _controller() async {
  SharedPreferences.setMockInitialValues({});
  FlutterSecureStorage.setMockInitialValues({
    'profile_index': '["s1"]',
    'active_profile': 's1',
    'p_s1_url': 'https://breeze.example.com',
    'p_s1_api_key': 'k',
    'p_s1_label': 'Sirocco-4820937',
    'p_s1_auth_version': '2',
  });
  final c = AppController(SecureStore());
  c.api = ApiClient(
    baseUrl: 'https://breeze.example.com',
    apiKey: 'k',
    client: MockClient((req) async => http.Response(
        jsonEncode(req.url.path == '/api/programs' ? _programs : <String, dynamic>{}), 200)),
  );
  return c;
}

Widget _host(AppController c, Widget child, double scale) => AppScope(
      controller: c,
      child: MaterialApp(
        builder: (context, app) => MediaQuery(
          data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)),
          child: app!,
        ),
        home: child,
      ),
    );

void _s25(WidgetTester tester, {double height = 832}) {
  tester.view.physicalSize = Size(1440, height * 3.75);
  tester.view.devicePixelRatio = 3.75;
  addTearDown(tester.view.reset);
}

/// How many lines [text] was laid out on.
int _lines(WidgetTester tester, String text) {
  final p = tester.renderObject<RenderParagraph>(find.text(text));
  final boxes = p.getBoxesForSelection(TextSelection(baseOffset: 0, extentOffset: text.length));
  return boxes.map((b) => b.top.round()).toSet().length;
}

void main() {
  for (final scale in [1.0, 1.3]) {
    group('at ${scale}x text', () {
      for (final p in _programs) {
        testWidgets('editing a ${p['kind']} fits, and the kind names stay whole', (tester) async {
          _s25(tester, height: 2400);
          final c = await _controller();
          await tester.pumpWidget(_host(c, ProgramEditScreen(units: _units, existing: Program.fromJson(p)), scale));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          for (final name in ['Favourite', 'Schedule', 'Curve']) {
            expect(_lines(tester, name), 1, reason: '"$name" broke across lines');
          }
        });
      }

      testWidgets('the programs list fits', (tester) async {
        _s25(tester);
        final c = await _controller();
        await tester.pumpWidget(_host(c, ProgramsScreen(units: _units), scale));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(find.text('Cosy evening'), findsOneWidget);
      });

      testWidgets('the Internal tab fits', (tester) async {
        _s25(tester, height: 3000);
        final c = await _controller();
        await tester.pumpWidget(_host(c, const Scaffold(body: InternalTab()), scale));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      });
    });
  }

  testWidgets('the kind picker says which kind is chosen', (tester) async {
    _s25(tester, height: 2400);
    final handle = tester.ensureSemantics();
    final c = await _controller();
    await tester.pumpWidget(_host(c, ProgramEditScreen(units: _units, existing: Program.fromJson(_programs[1])), 1.0));
    await tester.pumpAndSettle();
    expect(
      tester.getSemantics(find.text('Schedule')),
      isSemantics(isSelected: true, isButton: true, isInMutuallyExclusiveGroup: true, hasTapAction: true),
    );
    expect(
      tester.getSemantics(find.text('Curve')),
      isSemantics(isSelected: false, isButton: true, hasTapAction: true),
    );
    handle.dispose();
  });

  testWidgets('a favourite has no on/off: it applies the same either way', (tester) async {
    _s25(tester, height: 2400);
    final c = await _controller();
    await tester.pumpWidget(_host(c, ProgramEditScreen(units: _units, existing: Program.fromJson(_programs[0])), 1.0));
    await tester.pumpAndSettle();
    expect(find.text('RUNNING'), findsNothing);
  });

  for (final (name, build, height) in [
    ('the schedule editor', (List<UnitSummary> u) => ProgramEditScreen(units: u, existing: Program.fromJson(_programs[1])), 2400.0),
    ('the curve editor', (List<UnitSummary> u) => ProgramEditScreen(units: u, existing: Program.fromJson(_programs[2])), 2400.0),
    ('the programs list', (List<UnitSummary> u) => ProgramsScreen(units: u), 832.0),
    ('the Internal tab', (List<UnitSummary> u) => const Scaffold(body: InternalTab()), 3000.0),
  ]) {
    testWidgets('$name: every control named and big enough to hit', (tester) async {
      _s25(tester, height: height);
      final handle = tester.ensureSemantics();
      final c = await _controller();
      await tester.pumpWidget(_host(c, build(_units), 1.0));
      await tester.pumpAndSettle();
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      handle.dispose();
    });
  }
}
