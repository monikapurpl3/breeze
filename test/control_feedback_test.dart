import 'package:breeze/src/control_feedback.dart';
import 'package:breeze/src/models.dart';
import 'package:flutter_test/flutter_test.dart';

UnitState reply({
  required bool on,
  required String mode,
  List<String>? notApplied,
}) =>
    UnitState.fromJson({
      'id': 'u1',
      'name': 'Lijeva Soba',
      'ip': '192.168.1.73',
      'online': true,
      'power_state': on,
      'operational_mode': mode,
      'target_temperature': 28.5,
      'indoor_temperature': 24.5,
      'outdoor_temperature': null,
      'fan_speed': 102,
      'swing_mode': 'HORIZONTAL',
      'eco': false,
      'turbo': false,
      'not_applied': ?notApplied,
    });

void main() {
  test('flaps refused while heating: says it needs time, and whose doing it is', () {
    final m = notAppliedMessage(reply(on: true, mode: 'HEAT', notApplied: ['swing_mode']))!;
    expect(m, contains("didn't accept the flap change"));
    expect(m, contains('not Breeze Core'));
    expect(m, contains('until warm air is coming out'));
    expect(m, contains('Try again shortly'));
  });

  test('flaps refused while off: says units only move them while running', () {
    final m = notAppliedMessage(reply(on: false, mode: 'HEAT', notApplied: ['swing_mode']))!;
    expect(m, contains('only move their flaps while they are running'));
  });

  test('eco refused while heating: says the unit will not take it in this mode', () {
    final m = notAppliedMessage(reply(on: true, mode: 'HEAT', notApplied: ['eco']))!;
    expect(m, contains("didn't accept eco"));
    expect(m, contains('only while cooling, not while heating'));
  });

  test('two refusals are named together, each reason once', () {
    final m = notAppliedMessage(
        reply(on: true, mode: 'HEAT', notApplied: ['swing_mode', 'eco']))!;
    expect(m, contains('the flap change and eco'));
    expect('Try again shortly'.allMatches(m).length, 1);
  });

  test('nothing refused, or an older server that does not say: no message', () {
    expect(notAppliedMessage(reply(on: true, mode: 'HEAT', notApplied: [])), isNull);
    expect(notAppliedMessage(reply(on: true, mode: 'HEAT')), isNull);
  });

  test('a predicted state never inherits an old refusal', () {
    final s = reply(on: true, mode: 'HEAT', notApplied: ['swing_mode']);
    expect(s.copyWith(swingMode: 'VERTICAL').notApplied, isEmpty);
  });
}
