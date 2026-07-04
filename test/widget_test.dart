// Unit tests for the wire models (no Flutter binding required).
import 'package:flutter_test/flutter_test.dart';
import 'package:breeze/src/models.dart';

void main() {
  test('ClimateSettings.toJson omits null fields', () {
    final s = ClimateSettings(powerState: true, targetTemperature: 21.5);
    final j = s.toJson();
    expect(j['power_state'], true);
    expect(j['target_temperature'], 21.5);
    expect(j.containsKey('operational_mode'), false);
    expect(j.containsKey('fan_speed'), false);
  });

  test('Program round-trips kind + curve through toSpecJson', () {
    final p = Program(
      id: 'x1',
      name: 'Night',
      enabled: true,
      unitIds: ['1', '2'],
      kind: 'curve',
      schedule: [],
      curve: CurveConfig(points: [
        CurvePoint(time: '08:00', temperature: 24.0),
        CurvePoint(time: '22:00', temperature: 20.0),
      ]),
    );
    final j = p.toSpecJson();
    expect(j.containsKey('id'), false); // server assigns it
    expect(j['kind'], 'curve');
    expect((j['curve']['points'] as List).length, 2);
    expect(j['unit_ids'], ['1', '2']);
  });

  test('UnitState.fromJson parses ints and nullable temps', () {
    final s = UnitState.fromJson({
      'id': '1', 'name': 'D Soba', 'ip': '192.168.1.73',
      'online': true, 'power_state': false, 'operational_mode': 'COOL',
      'target_temperature': 22, 'indoor_temperature': null,
      'outdoor_temperature': 30.5, 'fan_speed': 102, 'swing_mode': 'BOTH',
      'eco': false, 'turbo': false,
    });
    expect(s.targetTemperature, 22.0);
    expect(s.indoorTemperature, isNull);
    expect(s.fanSpeed, 102);
  });
}
