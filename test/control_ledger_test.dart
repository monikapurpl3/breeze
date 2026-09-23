import 'package:breeze/src/control_ledger.dart';
import 'package:breeze/src/models.dart';
import 'package:flutter_test/flutter_test.dart';

UnitState at(double t, {String id = 'u1'}) => UnitState.fromJson({
      'id': id,
      'name': 'Dnevna Soba',
      'ip': '192.168.1.72',
      'online': true,
      'power_state': true,
      'operational_mode': 'HEAT',
      'target_temperature': t,
      'indoor_temperature': 22.0,
      'outdoor_temperature': null,
      'fan_speed': 102,
      'swing_mode': 'OFF',
      'eco': false,
      'turbo': false,
    });

void main() {
  test('a burst of taps shows only the newest reply, never an older one', () {
    // The bug, replayed: taps to 24.5 … 29, replies arriving in order.
    final l = ControlLedger();
    final tickets = [for (var i = 0; i < 10; i++) l.begin('u1')];
    for (var i = 0; i < 9; i++) {
      expect(l.replied('u1', tickets[i], at(24.5 + i * 0.5)), isNull,
          reason: 'reply ${i + 1} is older than the last tap and must not be shown');
    }
    expect(l.replied('u1', tickets[9], at(29))?.targetTemperature, 29);
  });

  test('a failure reverts to what the server last said, not to before its tap', () {
    // Tap to 25 (works), tap to 26 (fails): the display belongs at 25 — the
    // old code went back to "before this tap", which was the optimistic 25.5
    // or whatever the previous tap had drawn.
    final l = ControlLedger();
    final a = l.begin('u1');
    final b = l.begin('u1');
    l.replied('u1', a, at(25));
    expect(l.failed('u1', b, at(24))?.targetTemperature, 25);
  });

  test('an older tap failing does not touch the display', () {
    final l = ControlLedger();
    final a = l.begin('u1');
    l.begin('u1');
    expect(l.failed('u1', a, at(24)), isNull, reason: 'the newer tap will settle it');
  });

  test('with nothing ever confirmed, a failure falls back to the state before', () {
    final l = ControlLedger();
    final a = l.begin('u1');
    expect(l.failed('u1', a, at(22))?.targetTemperature, 22);
  });

  test('pushes are held back while a control is in flight, then allowed again', () {
    final l = ControlLedger();
    final a = l.begin('u1');
    expect(l.reported(at(24)), isFalse, reason: 'must not flash the old value mid-tap');
    expect(l.confirmed('u1')?.targetTemperature, 24, reason: 'but it is still recorded');
    l.replied('u1', a, at(26));
    l.settled('u1');
    expect(l.reported(at(26)), isTrue);
  });

  test('the unit stays busy until the last of overlapping taps settles', () {
    // The old code used a set: the first reply of a burst marked the unit
    // idle while later taps were still on their way.
    final l = ControlLedger();
    l.begin('u1');
    l.begin('u1');
    l.settled('u1');
    expect(l.isBusy('u1'), isTrue);
    l.settled('u1');
    expect(l.isBusy('u1'), isFalse);
  });

  test('units are independent', () {
    final l = ControlLedger();
    l.begin('u1');
    expect(l.isBusy('u2'), isFalse);
    expect(l.reported(at(20, id: 'u2')), isTrue);
    final b = l.begin('u2');
    expect(l.replied('u2', b, at(21, id: 'u2'))?.targetTemperature, 21);
  });

  test('forgetting a unit clears it', () {
    final l = ControlLedger();
    l.begin('u1');
    l.forget('u1');
    expect(l.isBusy('u1'), isFalse);
    expect(l.confirmed('u1'), isNull);
  });
}
