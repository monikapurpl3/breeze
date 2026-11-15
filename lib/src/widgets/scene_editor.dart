import 'package:material_ui/material_ui.dart';

import '../app_scope.dart';
import '../l10n.dart';
import '../models.dart';
import '../theme.dart';
import '../util.dart';
import 'big_toggle.dart';
import 'fan_control.dart';
import 'flap_control.dart';
import 'mode_selector.dart';
import 'power_switch.dart';
import 'temp_control.dart';

/// A whole scene -- everything a favourite or a schedule entry sets -- edited
/// with the control screen's own controls, so a scene is set up the way a
/// unit is used: the same mode picker, the same temperature, fan and flaps,
/// the same colours, and the same names for a screen reader.
///
/// Always emits a fully populated [ClimateSettings] through [onChanged].
class SceneEditor extends StatefulWidget {
  const SceneEditor({super.key, required this.initial, required this.onChanged});

  final ClimateSettings initial;
  final ValueChanged<ClimateSettings> onChanged;

  /// [s] with every field a scene needs filled in.
  static ClimateSettings complete(ClimateSettings s) {
    final c = s.copy();
    c.powerState ??= true;
    c.operationalMode ??= 'COOL';
    c.targetTemperature ??= 22.0;
    c.fanSpeed ??= 102;
    c.swingMode ??= 'OFF';
    c.eco ??= false;
    c.turbo ??= false;
    return c;
  }

  @override
  State<SceneEditor> createState() => _SceneEditorState();
}

class _SceneEditorState extends State<SceneEditor> {
  late ClimateSettings s = SceneEditor.complete(widget.initial);

  void _set(void Function(ClimateSettings) edit) {
    setState(() => edit(s));
    widget.onChanged(s.copy());
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final l = context.l10n;
    final accent = accentForMode(s.operationalMode!, scheme);
    final on = s.powerState!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(on ? l.sceneSwitchesOn : l.sceneSwitchesOff,
                      style: Theme.of(context).textTheme.titleMedium),
                  Text(
                    on
                        ? l.sceneWithEverythingBelow
                        : l.sceneSettingsStillSent,
                    style: Theme.of(context)
                        .textTheme
                        .bodySmall
                        ?.copyWith(color: scheme.onSurfaceVariant),
                  ),
                ],
              ),
            ),
            PowerSwitch(on: on, onChanged: (v) => _set((s) => s.powerState = v)),
          ],
        ),
        const SizedBox(height: 16),
        ModeSelector(
          value: s.operationalMode!,
          onChanged: (m) => _set((s) => s.operationalMode = m),
        ),
        const SizedBox(height: 8),
        TempControl(
          value: s.targetTemperature!,
          accent: accent,
          unit: AppScope.of(context).tempUnit,
          onChanged: (t) => _set((s) => s.targetTemperature = t),
        ),
        const SizedBox(height: 8),
        FanControl(
          value: s.fanSpeed!,
          accent: accent,
          onChanged: (f) => _set((s) => s.fanSpeed = f),
        ),
        const SizedBox(height: 4),
        FlapControl(
          value: s.swingMode!,
          accent: accent,
          onChanged: (v) => _set((s) => s.swingMode = v),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: BigToggle(
                label: l.labelEco,
                icon: Icons.eco,
                value: s.eco!,
                accent: const Color(0xFF4CAF50),
                onChanged: (v) => _set((s) => s.eco = v),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: BigToggle(
                label: l.labelTurbo,
                icon: Icons.bolt,
                value: s.turbo!,
                accent: const Color(0xFFFF7043),
                onChanged: (v) => _set((s) => s.turbo = v),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// A scene in a line of small coloured pills -- "heat · 22.0° · fan auto" --
/// for a list or a schedule entry, where the full editor would be too much.
class SceneSummary extends StatelessWidget {
  const SceneSummary({super.key, required this.settings});
  final ClimateSettings settings;

  static const _modeIcons = <String, IconData>{
    'AUTO': Icons.auto_mode,
    'COOL': Icons.ac_unit,
    'DRY': Icons.water_drop_outlined,
    'HEAT': Icons.local_fire_department,
    'FAN_ONLY': Icons.air,
  };

  /// The same, as words, for a screen reader and for one-line summaries: in
  /// [l]'s language, or English without one.
  static String describe(ClimateSettings raw, String unit, [AppLocalizations? l]) {
    l ??= lookupAppLocalizations(const Locale('en'));
    final s = SceneEditor.complete(raw);
    if (s.powerState == false) return l.stateOff;
    return [
      modeLabel(l, s.operationalMode!),
      fmtTemp(s.targetTemperature!, unit, showUnit: false),
      l.sceneFan(fanWord(s.fanSpeed!, l)),
      if (s.swingMode != 'OFF') l.sceneFlaps(swingLabel(l, s.swingMode!)),
      if (s.eco == true) l.labelEco.toLowerCase(),
      if (s.turbo == true) l.labelTurbo.toLowerCase(),
    ].join(' · ');
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final l = context.l10n;
    final unit = AppScope.of(context).tempUnit;
    final s = SceneEditor.complete(settings);
    final off = s.powerState == false;
    final accent = off ? scheme.error : accentForMode(s.operationalMode!, scheme);
    final ink = readableAccent(accent, scheme,
        on: layeredOnSurface(scheme, [accent.withValues(alpha: 0.16)]));
    Widget pill(String text, {IconData? icon, bool strong = false}) => Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: strong ? accent.withValues(alpha: 0.16) : scheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(icon, size: 15, color: strong ? ink : scheme.onSurfaceVariant),
                const SizedBox(width: 4),
              ],
              // Flexible: a long translation ("ventilator: srednje") wraps
              // inside its pill at large text sizes rather than overflowing.
              Flexible(
                child: Text(text,
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: strong ? FontWeight.w600 : FontWeight.w500,
                      color: strong ? ink : scheme.onSurface,
                    )),
              ),
            ],
          ),
        );
    return Semantics(
      label: describe(settings, unit, l),
      excludeSemantics: true,
      child: Wrap(
        spacing: 6,
        runSpacing: 6,
        children: off
            ? [pill(l.sceneOff, icon: Icons.power_settings_new, strong: true)]
            : [
                pill(modeLabel(l, s.operationalMode!),
                    icon: _modeIcons[s.operationalMode], strong: true),
                pill(fmtTemp(s.targetTemperature!, unit, showUnit: false), strong: true),
                pill(l.sceneFan(fanWord(s.fanSpeed!, l)), icon: Icons.air),
                if (s.swingMode != 'OFF')
                  pill(swingLabel(l, s.swingMode!), icon: Icons.swap_vert),
                if (s.eco == true) pill(l.labelEco.toLowerCase(), icon: Icons.eco),
                if (s.turbo == true) pill(l.labelTurbo.toLowerCase(), icon: Icons.bolt),
              ],
      ),
    );
  }
}

/// The fan speed in the fan slider's words: silent, low, medium, high, max --
/// or auto; in [l]'s language, or English without one.
String fanWord(int speed, [AppLocalizations? l]) {
  l ??= lookupAppLocalizations(const Locale('en'));
  // The nearest of the slider's five steps (20 ... 100), or 102 for auto.
  final step = speed >= 101 ? 102 : (speed / 20).round().clamp(1, 5) * 20;
  return fanSpeedLabel(l, step);
}
