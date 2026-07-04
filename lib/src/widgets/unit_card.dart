import 'package:flutter/material.dart';

import '../models.dart';
import '../theme.dart';
import 'dial.dart';

/// One unit's live control surface — mirrors the web UI panel.
class UnitCard extends StatelessWidget {
  final UnitState state;
  final bool busy;
  final ValueChanged<ClimateSettings> onControl;
  const UnitCard({super.key, required this.state, required this.busy, required this.onControl});

  String _nextSwing(String current, String axis) {
    var v = current == 'VERTICAL' || current == 'BOTH';
    var h = current == 'HORIZONTAL' || current == 'BOTH';
    if (axis == 'v') v = !v;
    if (axis == 'h') h = !h;
    if (v && h) return 'BOTH';
    if (v) return 'VERTICAL';
    if (h) return 'HORIZONTAL';
    return 'OFF';
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final accent = accentForMode(state.operationalMode, scheme);
    final vOn = state.swingMode == 'VERTICAL' || state.swingMode == 'BOTH';
    final hOn = state.swingMode == 'HORIZONTAL' || state.swingMode == 'BOTH';

    return Card(
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(Icons.circle, size: 10, color: state.online ? accent : scheme.error),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(state.name,
                      style: Theme.of(context)
                          .textTheme
                          .titleMedium
                          ?.copyWith(fontWeight: FontWeight.w600)),
                ),
                if (busy)
                  const Padding(
                    padding: EdgeInsets.only(right: 8),
                    child: SizedBox(
                        width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                  ),
                Switch(
                  value: state.powerState,
                  onChanged: busy ? null : (v) => onControl(ClimateSettings(powerState: v)),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Center(
              child: Dial(
                indoor: state.indoorTemperature,
                target: state.targetTemperature,
                accent: accent,
                online: state.online,
              ),
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                IconButton.filledTonal(
                  onPressed: busy || state.targetTemperature <= kMinTemp
                      ? null
                      : () => onControl(ClimateSettings(
                          targetTemperature:
                              (state.targetTemperature - 0.5).clamp(kMinTemp, kMaxTemp))),
                  icon: const Icon(Icons.remove),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Text('${state.targetTemperature.toStringAsFixed(1)}°',
                      style: Theme.of(context).textTheme.titleLarge),
                ),
                IconButton.filledTonal(
                  onPressed: busy || state.targetTemperature >= kMaxTemp
                      ? null
                      : () => onControl(ClimateSettings(
                          targetTemperature:
                              (state.targetTemperature + 0.5).clamp(kMinTemp, kMaxTemp))),
                  icon: const Icon(Icons.add),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: kModes
                  .map((m) => ChoiceChip(
                        label: Text(kModeLabels[m]!),
                        selected: state.operationalMode == m,
                        onSelected:
                            busy ? null : (_) => onControl(ClimateSettings(operationalMode: m)),
                      ))
                  .toList(),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: kFanSpeeds
                  .map((f) => ChoiceChip(
                        label: Text(kFanLabels[f]!),
                        selected: state.fanSpeed == f,
                        onSelected: busy ? null : (_) => onControl(ClimateSettings(fanSpeed: f)),
                      ))
                  .toList(),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _toggle(context, 'eco', state.eco,
                    busy ? null : () => onControl(ClimateSettings(eco: !state.eco))),
                _toggle(context, 'turbo', state.turbo,
                    busy ? null : () => onControl(ClimateSettings(turbo: !state.turbo))),
                _toggle(context, 'flap ↕', vOn,
                    busy ? null : () => onControl(ClimateSettings(swingMode: _nextSwing(state.swingMode, 'v')))),
                _toggle(context, 'flap ↔', hOn,
                    busy ? null : () => onControl(ClimateSettings(swingMode: _nextSwing(state.swingMode, 'h')))),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _toggle(BuildContext context, String label, bool on, VoidCallback? onTap) {
    return FilterChip(
      label: Text(label),
      selected: on,
      onSelected: onTap == null ? null : (_) => onTap(),
    );
  }
}
