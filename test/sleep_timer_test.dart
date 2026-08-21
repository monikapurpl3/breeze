import 'package:breeze/src/models.dart';
import 'package:breeze/src/native_licenses.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('SleepTimer', () {
    SleepTimer make(int secondsRemaining, {String firesAt = '2026-08-21T23:15:00'}) =>
        SleepTimer.fromJson({
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
      final t = SleepTimer.fromJson({'id': 'x', 'unit_ids': []});
      expect(t.remaining, 0);
      expect(t.minutes, 0);
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
