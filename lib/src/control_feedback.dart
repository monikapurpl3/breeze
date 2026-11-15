import 'l10n.dart' show AppLocalizations;
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
String? notAppliedMessage(AppLocalizations l, UnitState s) {
  final fields = s.notApplied;
  if (fields.isEmpty) return null;
  final reasons = <String>[];
  for (final f in fields) {
    final r = _reasonFor(l, f, s);
    if (!reasons.contains(r)) reasons.add(r);
  }
  return l.controlNotApplied(_joinNames(l, fields), reasons.join(' '));
}

String _nameOf(AppLocalizations l, String field) => switch (field) {
      'swing_mode' => l.controlNameSwing,
      'eco' => l.controlNameEco,
      'turbo' => l.controlNameTurbo,
      'fan_speed' => l.controlNameFanSpeed,
      'target_temperature' => l.controlNameTemperature,
      'operational_mode' => l.controlNameMode,
      'power_state' => l.controlNamePower,
      _ => field.replaceAll('_', ' '),
    };

String _joinNames(AppLocalizations l, List<String> fields) {
  final n = [for (final f in fields) _nameOf(l, f)];
  if (n.length <= 1) return n.isEmpty ? l.controlNameChange : n.first;
  final rest = n.sublist(1, n.length - 1).fold(n.first, l.controlNamesList);
  return l.controlNamesAnd(rest, n.last);
}

String _reasonFor(AppLocalizations l, String field, UnitState s) {
  final heating = s.operationalMode == 'HEAT';
  switch (field) {
    case 'swing_mode':
      if (!s.powerState) return l.controlReasonSwingOff;
      if (heating) return l.controlReasonSwingHeating;
      return l.controlReasonSwingWait;
    case 'eco':
      return heating ? l.controlReasonEcoHeating : l.controlReasonEcoModes;
    case 'turbo':
      return l.controlReasonTurboModes;
    default:
      return l.controlReasonOther;
  }
}
