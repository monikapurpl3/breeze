import 'package:material_ui/material_ui.dart';

import '../app_info.dart';
import '../app_scope.dart';
import '../haptics.dart';
import '../l10n.dart';
import 'nerd_screen.dart';
import 'servers_screen.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  /// Taps on the version row. Seven opens the Nerd screen — the same gesture
  /// Android itself uses for developer options, so it's discoverable by
  /// instinct and invisible otherwise.
  int _versionTaps = 0;
  DateTime? _lastTap;

  Future<bool> _confirm(BuildContext context, String title, String body) async {
    return await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: Text(title),
            content: Text(body),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(ctx.l10n.actionCancel)),
              FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(ctx.l10n.settingsConfirm)),
            ],
          ),
        ) ??
        false;
  }

  /// Seven taps opens the Nerd screen. The run resets after a couple of
  /// seconds of hesitation so an idle poke days apart can't accumulate into
  /// an accidental unlock.
  void _onVersionTap() {
    final now = DateTime.now();
    if (_lastTap != null && now.difference(_lastTap!) > const Duration(seconds: 2)) {
      _versionTaps = 0;
    }
    _lastTap = now;
    _versionTaps++;

    if (_versionTaps >= 7) {
      _versionTaps = 0;
      Haptics.success();
      Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const NerdScreen()),
      );
      return;
    }
    // Say nothing for the first few, then count down like Android does —
    // silent enough not to be noise, loud enough to feel intentional.
    final left = 7 - _versionTaps;
    if (left <= 3) {
      Haptics.tick();
      ScaffoldMessenger.of(context)
        ..removeCurrentSnackBar()
        ..showSnackBar(SnackBar(
          duration: const Duration(milliseconds: 700),
          content: Text(left == 1
              ? context.l10n.settingsNerdOneMoreTap
              : context.l10n.settingsNerdTapsLeft(left)),
        ));
    }
  }

  /// The language a tag names, by its own name; "System default" for none.
  String _languageName(BuildContext context, String? tag) {
    if (tag == null) return context.l10n.languageSystem;
    for (final l in appLanguages) {
      if (l.tag == tag) return l.name;
    }
    return tag;
  }

  Future<void> _pickLanguage(BuildContext context, String? current) async {
    final c = AppScope.of(context);
    // A one-element list, so "chose System default" (null) differs from
    // "closed the dialog" (no list at all).
    final chosen = await showDialog<List<String?>>(
      context: context,
      builder: (ctx) {
        Widget option(String? tag, String name) => ListTile(
              title: Text(name),
              selected: tag == current,
              trailing: tag == current ? const Icon(Icons.check) : null,
              onTap: () => Navigator.pop(ctx, [tag]),
            );
        return SimpleDialog(
          title: Text(ctx.l10n.language),
          children: [
            option(null, ctx.l10n.languageSystem),
            for (final l in appLanguages) option(l.tag, l.name),
          ],
        );
      },
    );
    if (chosen == null || chosen.first == current) return;
    Haptics.select();
    await c.setLanguage(chosen.first);
  }

  @override
  Widget build(BuildContext context) {
    final c = AppScope.of(context);
    final scheme = Theme.of(context).colorScheme;
    final server = c.api?.baseUrl ?? '—';
    final l = context.l10n;

    return Scaffold(
      appBar: AppBar(title: Text(l.settingsTitle)),
      body: ListView(
        children: [
          const SizedBox(height: 8),
          ListTile(
            leading: const Icon(Icons.dns_outlined),
            title: Text(l.settingsServer),
            subtitle: Text(c.profiles.length > 1
                ? '''$server
${l.settingsServersSaved(c.profiles.length)}'''
                : server),
            isThreeLine: c.profiles.length > 1,
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              Haptics.tick();
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const ServersScreen()),
              );
            },
          ),
          ListTile(
            leading: const Icon(Icons.smartphone_outlined),
            title: Text(l.settingsThisDevice),
            subtitle: Text(c.deviceLabel),
          ),
          const Divider(),
          // --- Display preferences ---
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Text(l.settingsDisplay, style: Theme.of(context).textTheme.labelLarge
                ?.copyWith(color: scheme.primary)),
          ),
          ListTile(
            leading: const Icon(Icons.translate),
            title: Text(context.l10n.language),
            subtitle: Text(_languageName(context, c.language)),
            onTap: () => _pickLanguage(context, c.language),
          ),
          ListTile(
            leading: const Icon(Icons.brightness_6_outlined),
            title: Text(l.settingsTheme),
            subtitle: Text(l.settingsThemeHint),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: SegmentedButton<ThemeMode>(
              segments: [
                ButtonSegment(value: ThemeMode.system, label: Text(l.settingsThemeSystem), icon: const Icon(Icons.phone_android)),
                ButtonSegment(value: ThemeMode.light, label: Text(l.settingsThemeLight), icon: const Icon(Icons.light_mode)),
                ButtonSegment(value: ThemeMode.dark, label: Text(l.settingsThemeDark), icon: const Icon(Icons.dark_mode)),
              ],
              selected: {c.themeMode},
              onSelectionChanged: (s) => c.setThemeMode(s.first),
            ),
          ),
          SwitchListTile(
            secondary: const Icon(Icons.contrast),
            title: Text(l.settingsPureBlack),
            subtitle: Text(l.settingsPureBlackHint),
            value: c.pureBlack,
            onChanged: c.setPureBlack,
          ),
          ListTile(
            leading: const Icon(Icons.thermostat_outlined),
            title: Text(l.settingsTempUnit),
            subtitle: Text(l.settingsTempUnitHint),
            trailing: SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'C', label: Text('°C')),
                ButtonSegment(value: 'F', label: Text('°F')),
              ],
              selected: {c.tempUnit},
              onSelectionChanged: (s) => c.setTempUnit(s.first),
            ),
          ),
          const Divider(),
          // --- Behaviour ---
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Text(l.settingsBehaviour, style: Theme.of(context).textTheme.labelLarge
                ?.copyWith(color: scheme.primary)),
          ),
          SwitchListTile(
            secondary: const Icon(Icons.volume_up_outlined),
            title: Text(l.settingsBeep),
            subtitle: Text(l.settingsBeepHint),
            value: c.beep,
            onChanged: c.setBeep,
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.refresh),
            title: Text(l.settingsRepair),
            subtitle: Text(l.settingsRepairHint),
            onTap: () async {
              if (await _confirm(context, l.settingsRepairTitle,
                  l.settingsRepairBody)) {
                if (!context.mounted) return;
                final nav = Navigator.of(context);
                await c.unpair();
                nav.popUntil((r) => r.isFirst);
              }
            },
          ),
          ListTile(
            leading: Icon(Icons.swap_horiz, color: scheme.error),
            title: Text(l.settingsForgetServer, style: TextStyle(color: scheme.error)),
            subtitle: Text(l.settingsForgetServerHint),
            onTap: () async {
              if (await _confirm(context, l.settingsForgetServerTitle,
                  l.settingsForgetServerBody)) {
                if (!context.mounted) return;
                final nav = Navigator.of(context);
                await c.changeServer();
                nav.popUntil((r) => r.isFirst);
              }
            },
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.info_outline),
            title: const Text('Breeze'),
            subtitle: Text(AppInfo.version),
            onTap: _onVersionTap,
          ),
          ListTile(
            leading: const Icon(Icons.description_outlined),
            title: Text(l.settingsLicences),
            subtitle: Text(l.settingsLicencesHint),
            onTap: () {
              Haptics.tick();
              showLicensePage(
                context: context,
                applicationName: 'Breeze',
                applicationVersion: AppInfo.version,
                applicationLegalese: l.settingsLegalese,
              );
            },
          ),
        ],
      ),
    );
  }
}
