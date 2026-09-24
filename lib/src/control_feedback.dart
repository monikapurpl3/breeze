import 'models.dart';

/// Explains, in words, a change the air conditioner refused.
///
/// A unit that ignores part of a command still answers it, with its state
/// unchanged, so a refused change used to look like a control springing back —
/// indistinguishable from a bug. Breeze Core 4.1.1 says which fields the unit
/// did not take (`not_applied` in the control reply), and this turns that into
/// a sentence that is clear about whose doing it was.
///
/// The reasons are what was measured on real units: none moves its flaps while
/// switched off; while heating, most hold the flaps still until warm air is
/// coming out and ignore flap changes until then (in fan, dry, cool and auto
/// they change at once); and many offer eco only while cooling.
///
/// Kept word for word in step with the web panel's `static/js/feedback.js`, so
/// the two clients say the same thing about the same refusal.
String? notAppliedMessage(UnitState s) {
  final fields = s.notApplied;
  if (fields.isEmpty) return null;
  final reasons = <String>[];
  for (final f in fields) {
    final r = _reasonFor(f, s);
    if (!reasons.contains(r)) reasons.add(r);
  }
  return "The air conditioner didn't accept ${_joinNames(fields)}"
      ' — the unit refused it, not Breeze Core. ${reasons.join(' ')}';
}

const _names = {
  'swing_mode': 'the flap change',
  'eco': 'eco',
  'turbo': 'turbo',
  'fan_speed': 'the fan speed',
  'target_temperature': 'the temperature',
  'operational_mode': 'the mode',
  'power_state': 'the power change',
};

String _joinNames(List<String> fields) {
  final n = [for (final f in fields) _names[f] ?? f.replaceAll('_', ' ')];
  if (n.length <= 1) return n.isEmpty ? 'the change' : n.first;
  return '${n.sublist(0, n.length - 1).join(', ')} and ${n.last}';
}

String _reasonFor(String field, UnitState s) {
  final heating = s.operationalMode == 'HEAT';
  switch (field) {
    case 'swing_mode':
      if (!s.powerState) return 'Units only move their flaps while they are running.';
      if (heating) {
        return 'While heating, it holds its flaps still until warm air is coming out, '
            'which can take a few minutes after switching on or into heating. Try again shortly.';
      }
      return 'It may need a moment before it will take this. Try again shortly.';
    case 'eco':
      return heating
          ? 'Many units offer eco only while cooling, not while heating.'
          : 'Many units offer eco only in some modes.';
    case 'turbo':
      return 'Many units offer turbo only in some modes.';
    default:
      return 'It does not take this in its current mode.';
  }
}
