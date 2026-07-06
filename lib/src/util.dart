import 'package:flutter/material.dart';

String hhmm(TimeOfDay t) =>
    '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

TimeOfDay parseHHMM(String s) {
  final p = s.split(':');
  return TimeOfDay(hour: int.parse(p[0]), minute: int.parse(p[1]));
}

int minutesOf(String s) {
  final p = s.split(':');
  return int.parse(p[0]) * 60 + int.parse(p[1]);
}

/// Snap to the nearest 0.5°, clamped to [16, 30].
double snapHalf(double t) => (t * 2).round() / 2.0;

/// Celsius -> Fahrenheit.
double toF(double c) => c * 9 / 5 + 32;

/// Format a Celsius value for display in the user's chosen unit. The wire
/// contract is always Celsius; this is display-only. `unit` is 'C' or 'F'.
/// With [showUnit] the result ends in °C/°F, otherwise just a degree sign.
String fmtTemp(double celsius, String unit, {bool showUnit = true}) {
  final f = unit == 'F';
  final v = (f ? toF(celsius) : celsius).toStringAsFixed(1);
  return showUnit ? '$v°${f ? 'F' : 'C'}' : '$v°';
}
