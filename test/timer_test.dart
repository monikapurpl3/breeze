import 'package:breeze/src/models.dart';
import 'package:breeze/src/native_licenses.dart';
import 'package:breeze/src/widgets/timer_sheet.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('UnitTimer', () {
    UnitTimer make(int secondsRemaining, {String firesAt = '2026-08-21T23:15:00'}) =>
        UnitTimer.fromJson({
          'id': 'abc123',
          'unit_ids': ['u1'],
          'minutes': 45,
          'fires_at': firesAt,
          'seconds_remaining': secondsRemaining,
        });

    test('counts down from the server figure, not the phone clock', () {
      // The whole point of seconds_remaining: a phone whose clock is a day out
      // still shows the right countdown, because only ELAPSED time is local.
      final t = make(2700);
      expect(t.remaining, inInclusiveRange(2699, 2700));
      expect(t.expired, isFalse);
    });

    test('never goes negative', () {
      expect(make(0).remaining, 0);
      expect(make(0).expired, isTrue);
    });

    test('short label reads like a human wrote it', () {
      expect(make(40).shortLabel, '40s');
      expect(make(45 * 60).shortLabel, '45m');
      expect(make(60 * 60).shortLabel, '1h');
      expect(make(80 * 60).shortLabel, '1h 20m');
    });

    test('fires-at clock is taken verbatim, not reinterpreted', () {
      // The string is already the SERVER's local wall clock. Parsing it as a
      // local DateTime here would shift it by the phone's offset and show the
      // wrong time to anyone in a different zone from their server.
      expect(make(60, firesAt: '2026-08-21T23:15:00').firesAtClock, '23:15');
      expect(make(60, firesAt: 'nonsense').firesAtClock, 'nonsense');
    });

    test('survives a response missing the optional fields', () {
      final t = UnitTimer.fromJson({'id': 'x', 'unit_ids': []});
      expect(t.remaining, 0);
      expect(t.minutes, 0);
    });
  });

  group('scheduled start', () {
    // A server "now" of [serverNow] is expressed the only way the wire carries
    // it: fires_at, and the seconds the server says are left.
    UnitTimer start(String firesAt, String serverNow) {
      final f = DateTime.parse('${firesAt}Z');
      final n = DateTime.parse('${serverNow}Z');
      return UnitTimer.fromJson({
        'id': 's1',
        'unit_ids': ['u1'],
        'minutes': f.difference(n).inMinutes,
        'fires_at': firesAt,
        'seconds_remaining': f.difference(n).inSeconds,
        'kind': 'start',
      });
    }

    test('kind decides which it is, and a missing kind means sleep', () {
      expect(start('2026-09-29T07:30:00', '2026-09-27T17:00:00').isStart, isTrue);
      // What a server older than 4.2.0 sends.
      expect(UnitTimer.fromJson({'id': 'x', 'unit_ids': []}).isStart, isFalse);
      expect(
        UnitTimer.fromJson({'id': 'x', 'unit_ids': [], 'kind': 'sleep'}).isStart,
        isFalse,
      );
    });

    test("says today, tomorrow, or the date, by the server's calendar", () {
      final today = start('2026-09-27T18:05:00', '2026-09-27T17:00:00');
      expect(today.daysAhead, 0);
      expect(today.whenLabel, 'today at 18:05');
      expect(today.shortWhen, '18:05');

      // Twenty minutes away, but past midnight: that is tomorrow.
      final late = start('2026-09-28T00:10:00', '2026-09-27T23:50:00');
      expect(late.daysAhead, 1);
      expect(late.whenLabel, 'tomorrow at 00:10');

      final monthEnd = start('2026-10-01T07:00:00', '2026-09-30T22:00:00');
      expect(monthEnd.whenLabel, 'tomorrow at 07:00');

      final later = start('2026-09-29T07:30:00', '2026-09-27T17:00:00');
      expect(later.daysAhead, 2);
      expect(later.whenLabel, 'Tue 29 Sep at 07:30');
      expect(later.shortWhen, 'Tue');

      final far = start('2026-10-20T07:00:00', '2026-09-27T07:00:00');
      expect(far.daysAhead, 23);
      expect(far.whenLabel, 'Tue 20 Oct at 07:00');
      expect(far.shortWhen, '20 Oct');
    });

    test('an unreadable fires_at does not throw', () {
      final t = UnitTimer.fromJson(
        {'id': 'x', 'unit_ids': [], 'kind': 'start', 'fires_at': 'soon'},
      );
      expect(t.daysAhead, isNull);
      expect(t.whenLabel, 'at soon');
    });
  });

  group('TimerSheet', () {
    /// Opens the sheet from a button and records what it returns.
    Future<void> open(
      WidgetTester tester,
      void Function(TimerChoice?) onResult, {
      UnitTimer? start,
      bool startsSupported = true,
    }) async {
      await tester.pumpWidget(MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async => onResult(await TimerSheet.show(
              context,
              unitName: 'Lijeva soba',
              start: start,
              startsSupported: startsSupported,
            )),
            child: const Text('open'),
          ),
        ),
      ));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
    }

    Future<void> tapText(WidgetTester tester, String text) async {
      await tester.ensureVisible(find.text(text));
      await tester.tap(find.text(text));
      await tester.pumpAndSettle();
    }

    testWidgets('an older server gets no turn-on half', (tester) async {
      await open(tester, (_) {}, startsSupported: false);
      expect(find.text('Turn off later'), findsOneWidget);
      expect(find.text('Turn on later'), findsNothing);
    });

    testWidgets('turn on then asks for tomorrow at seven by default', (tester) async {
      TimerChoice? chosen;
      await open(tester, (c) => chosen = c);
      expect(find.text('Turn on later'), findsOneWidget);
      expect(find.text('Tomorrow'), findsOneWidget);
      expect(find.text('07:00'), findsOneWidget);
      await tapText(tester, 'Turn on then');
      expect(chosen, isA<StartAt>());
      final s = chosen as StartAt;
      expect((s.days, s.at), (1, '07:00'));
    });

    testWidgets('a pending start opens on its own day and time', (tester) async {
      final pending = UnitTimer.fromJson({
        'id': 's1',
        'unit_ids': ['u1'],
        'fires_at': '2026-09-30T06:15:00',
        // Three days out, from the server's 2026-09-27T06:15.
        'seconds_remaining': 3 * 86400,
        'kind': 'start',
      });
      TimerChoice? chosen;
      await open(tester, (c) => chosen = c, start: pending);
      expect(find.text('Turning on Wed 30 Sep at 06:15'), findsOneWidget);
      expect(find.text('In 3 days'), findsOneWidget);
      expect(find.text('06:15'), findsOneWidget);
      await tapText(tester, 'Cancel the start');
      expect(chosen, isA<CancelTimer>());
      expect((chosen as CancelTimer).timer.id, 's1');
    });

    testWidgets('a preset still sets a sleep timer', (tester) async {
      TimerChoice? chosen;
      await open(tester, (c) => chosen = c);
      await tapText(tester, '45 min');
      expect(chosen, isA<SleepFor>());
      expect((chosen as SleepFor).minutes, 45);
    });
  });

  test('native (Gradle) licences are registered for the licence page', () async {
    // Flutter's LicenseRegistry only walks the Dart package graph, so without
    // registerNativeLicenses() the AndroidX Car App Library the Android Auto
    // surface is built on has no attribution anywhere in the app.
    TestWidgetsFlutterBinding.ensureInitialized();
    registerNativeLicenses();
    final packages = <String>[];
    var sawApache = false;
    await for (final entry in LicenseRegistry.licenses) {
      packages.addAll(entry.packages);
      if (entry.packages.contains('androidx.car.app:app')) {
        sawApache = entry.paragraphs.any(
          (p) => p.text.contains('Apache License'),
        );
      }
    }
    expect(packages, contains('androidx.car.app:app'));
    expect(packages, contains('androidx.car.app:app-projected'));
    expect(sawApache, isTrue, reason: 'the Apache-2.0 text should be included');
  });
}
