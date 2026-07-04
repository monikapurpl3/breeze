import 'package:flutter/material.dart';

import '../models.dart';

/// Edits a full climate "scene" (used by favourites and schedule entries).
/// Produces a fully-populated ClimateSettings via [onChanged].
class ClimateSettingsEditor extends StatefulWidget {
  final ClimateSettings initial;
  final ValueChanged<ClimateSettings> onChanged;
  const ClimateSettingsEditor({super.key, required this.initial, required this.onChanged});

  @override
  State<ClimateSettingsEditor> createState() => _ClimateSettingsEditorState();
}

class _ClimateSettingsEditorState extends State<ClimateSettingsEditor> {
  late ClimateSettings s;

  @override
  void initState() {
    super.initState();
    // ensure all fields have a concrete value for a scene
    s = widget.initial.copy();
    s.powerState ??= true;
    s.operationalMode ??= 'COOL';
    s.targetTemperature ??= 22.0;
    s.fanSpeed ??= 102;
    s.swingMode ??= 'OFF';
    s.eco ??= false;
    s.turbo ??= false;
  }

  void _emit() => widget.onChanged(s.copy());

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Power'),
          value: s.powerState!,
          onChanged: (v) => setState(() { s.powerState = v; _emit(); }),
        ),
        const SizedBox(height: 4),
        Text('Mode', style: Theme.of(context).textTheme.labelLarge),
        Wrap(
          spacing: 8,
          children: kModes
              .map((m) => ChoiceChip(
                    label: Text(kModeLabels[m]!),
                    selected: s.operationalMode == m,
                    onSelected: (_) => setState(() { s.operationalMode = m; _emit(); }),
                  ))
              .toList(),
        ),
        const SizedBox(height: 12),
        Row(children: [
          Text('Target', style: Theme.of(context).textTheme.labelLarge),
          const Spacer(),
          Text('${s.targetTemperature!.toStringAsFixed(1)}°'),
        ]),
        Slider(
          min: kMinTemp,
          max: kMaxTemp,
          divisions: ((kMaxTemp - kMinTemp) * 2).round(),
          value: s.targetTemperature!.clamp(kMinTemp, kMaxTemp),
          label: '${s.targetTemperature!.toStringAsFixed(1)}°',
          onChanged: (v) => setState(() { s.targetTemperature = (v * 2).round() / 2; _emit(); }),
        ),
        Text('Fan', style: Theme.of(context).textTheme.labelLarge),
        Wrap(
          spacing: 8,
          children: kFanSpeeds
              .map((f) => ChoiceChip(
                    label: Text(kFanLabels[f]!),
                    selected: s.fanSpeed == f,
                    onSelected: (_) => setState(() { s.fanSpeed = f; _emit(); }),
                  ))
              .toList(),
        ),
        const SizedBox(height: 12),
        Text('Swing', style: Theme.of(context).textTheme.labelLarge),
        Wrap(
          spacing: 8,
          children: kSwingModes
              .map((sw) => ChoiceChip(
                    label: Text(sw.toLowerCase()),
                    selected: s.swingMode == sw,
                    onSelected: (_) => setState(() { s.swingMode = sw; _emit(); }),
                  ))
              .toList(),
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Eco'),
          value: s.eco!,
          onChanged: (v) => setState(() { s.eco = v; _emit(); }),
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Turbo'),
          value: s.turbo!,
          onChanged: (v) => setState(() { s.turbo = v; _emit(); }),
        ),
      ],
    );
  }
}
