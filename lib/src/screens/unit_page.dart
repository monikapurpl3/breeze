import 'package:flutter/material.dart';

import '../app_scope.dart';
import '../models.dart';
import '../theme.dart';
import '../widgets/big_toggle.dart';
import '../widgets/fan_control.dart';
import '../widgets/flap_control.dart';
import '../widgets/mode_selector.dart';
import '../widgets/temp_control.dart';

/// One AC unit, filling the screen (no scrolling). Composed of the modern
/// control widgets; every change is a partial [ClimateSettings] delta handed
/// up via [onControl]. Rebuilds cheaply from an immutable [state]; the
/// interactive children hold their own drag state so a background refresh
/// never yanks a control the user is touching.
class UnitPage extends StatelessWidget {
  const UnitPage({
    super.key,
    required this.state,
    required this.onControl,
    this.refreshing = false,
    this.onRename,
    this.onRemove,
  });

  final UnitState state;
  final ValueChanged<ClimateSettings> onControl;
  final bool refreshing;
  final VoidCallback? onRename;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final accent = accentForMode(state.operationalMode, scheme);
    final unit = AppScope.of(context).tempUnit;
    final online = state.online;
    // Controls are live when the unit is reachable. (You can still retarget a
    // powered-off unit; only an unreachable one locks everything out.)
    final live = online;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
      child: Column(
        children: [
          // ---- header: status · name · refresh · power · menu ----
          Row(
            children: [
              Icon(Icons.circle, size: 10, color: online ? accent : scheme.error),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  state.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                ),
              ),
              // Discreet refresh indicator — tiny, only while updating.
              AnimatedOpacity(
                duration: const Duration(milliseconds: 150),
                opacity: refreshing ? 1 : 0,
                child: SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2, color: accent),
                ),
              ),
              const SizedBox(width: 8),
              _PowerButton(
                on: state.powerState,
                accent: accent,
                enabled: live,
                onTap: () => onControl(ClimateSettings(powerState: !state.powerState)),
              ),
              if (onRename != null || onRemove != null)
                PopupMenuButton<String>(
                  onSelected: (v) {
                    if (v == 'rename') onRename?.call();
                    if (v == 'remove') onRemove?.call();
                  },
                  itemBuilder: (_) => [
                    if (onRename != null)
                      const PopupMenuItem(value: 'rename', child: Text('Rename')),
                    if (onRemove != null)
                      const PopupMenuItem(value: 'remove', child: Text('Remove')),
                  ],
                ),
            ],
          ),
          if (!online)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text('offline — last known settings',
                  style: TextStyle(color: scheme.error, fontSize: 13)),
            ),

          // ---- temperature hero (absorbs slack so the page fills) ----
          Expanded(
            child: TempControl(
              value: state.targetTemperature,
              indoor: state.indoorTemperature,
              accent: accent,
              unit: unit,
              enabled: live,
              onChanged: (t) => onControl(ClimateSettings(targetTemperature: t)),
            ),
          ),

          // ---- mode ----
          ModeSelector(
            value: state.operationalMode,
            enabled: live,
            onChanged: (m) => onControl(ClimateSettings(operationalMode: m)),
          ),
          const SizedBox(height: 12),

          // ---- fan ----
          FanControl(
            value: state.fanSpeed,
            accent: accent,
            enabled: live,
            onChanged: (f) => onControl(ClimateSettings(fanSpeed: f)),
          ),
          const SizedBox(height: 4),

          // ---- flap ----
          FlapControl(
            value: state.swingMode,
            accent: accent,
            enabled: live,
            onChanged: (s) => onControl(ClimateSettings(swingMode: s)),
          ),
          const SizedBox(height: 12),

          // ---- eco / turbo ----
          Row(
            children: [
              Expanded(
                child: BigToggle(
                  label: 'Eco',
                  icon: Icons.eco,
                  value: state.eco,
                  accent: const Color(0xFF4CAF50),
                  enabled: live,
                  onChanged: (v) => onControl(ClimateSettings(eco: v)),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: BigToggle(
                  label: 'Turbo',
                  icon: Icons.bolt,
                  value: state.turbo,
                  accent: const Color(0xFFFF7043),
                  enabled: live,
                  onChanged: (v) => onControl(ClimateSettings(turbo: v)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _PowerButton extends StatelessWidget {
  const _PowerButton({
    required this.on,
    required this.accent,
    required this.enabled,
    required this.onTap,
  });
  final bool on;
  final Color accent;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      width: 46,
      height: 46,
      child: Material(
        color: on && enabled
            ? accent.withValues(alpha: 0.18)
            : scheme.surfaceContainerHighest.withValues(alpha: 0.5),
        shape: const CircleBorder(),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: enabled ? onTap : null,
          child: Icon(
            Icons.power_settings_new,
            color: !enabled
                ? scheme.onSurfaceVariant.withValues(alpha: 0.4)
                : (on ? accent : scheme.onSurfaceVariant),
          ),
        ),
      ),
    );
  }
}
