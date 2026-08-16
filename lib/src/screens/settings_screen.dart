import 'package:flutter/material.dart';

import '../app_info.dart';
import '../app_scope.dart';
import '../haptics.dart';
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
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
              FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Confirm')),
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
              ? 'One more tap…'
              : '$left taps until you are a nerd'),
        ));
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = AppScope.of(context);
    final scheme = Theme.of(context).colorScheme;
    final server = c.api?.baseUrl ?? '—';

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        children: [
          const SizedBox(height: 8),
          ListTile(
            leading: const Icon(Icons.dns_outlined),
            title: const Text('Server'),
            subtitle: Text(c.profiles.length > 1
                ? '''$server
${c.profiles.length} saved — tap to switch'''
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
            title: const Text('This device'),
            subtitle: Text(c.deviceLabel),
          ),
          const Divider(),
          // --- Display preferences ---
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Text('Display', style: Theme.of(context).textTheme.labelLarge
                ?.copyWith(color: scheme.primary)),
          ),
          ListTile(
            leading: const Icon(Icons.brightness_6_outlined),
            title: const Text('Theme'),
            subtitle: const Text('Follow system, or force light / dark'),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: SegmentedButton<ThemeMode>(
              segments: const [
                ButtonSegment(value: ThemeMode.system, label: Text('System'), icon: Icon(Icons.phone_android)),
                ButtonSegment(value: ThemeMode.light, label: Text('Light'), icon: Icon(Icons.light_mode)),
                ButtonSegment(value: ThemeMode.dark, label: Text('Dark'), icon: Icon(Icons.dark_mode)),
              ],
              selected: {c.themeMode},
              onSelectionChanged: (s) => c.setThemeMode(s.first),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.thermostat_outlined),
            title: const Text('Temperature unit'),
            subtitle: const Text('Display only — the server always uses Celsius'),
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
            child: Text('Behaviour', style: Theme.of(context).textTheme.labelLarge
                ?.copyWith(color: scheme.primary)),
          ),
          SwitchListTile(
            secondary: const Icon(Icons.volume_up_outlined),
            title: const Text('Beep on control'),
            subtitle: const Text('Make the unit chirp when it accepts a command'),
            value: c.beep,
            onChanged: c.setBeep,
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.refresh),
            title: const Text('Re-pair this device'),
            subtitle: const Text('Get a new pairing code and re-authorise'),
            onTap: () async {
              if (await _confirm(context, 'Re-pair device?',
                  'This forgets the current access token and starts pairing again.')) {
                if (!context.mounted) return;
                final nav = Navigator.of(context);
                await c.unpair();
                nav.popUntil((r) => r.isFirst);
              }
            },
          ),
          ListTile(
            leading: Icon(Icons.swap_horiz, color: scheme.error),
            title: Text('Forget this server', style: TextStyle(color: scheme.error)),
            subtitle: const Text('Erase its address, key and credential from this phone'),
            onTap: () async {
              if (await _confirm(context, 'Forget this server?',
                  'This erases the stored server address, access key and device '
                  'credential. Other saved servers are untouched.')) {
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
            title: const Text('Licences'),
            subtitle: const Text('Open-source licences for this app'),
            onTap: () {
              Haptics.tick();
              showLicensePage(
                context: context,
                applicationName: 'Breeze',
                applicationVersion: AppInfo.version,
                applicationLegalese:
                    'AGPL-3.0-or-later. A client for a self-hosted Breeze Core '
                    'server; requests are signed per-device with an Ed25519 key '
                    'that never leaves this phone.',
              );
            },
          ),
        ],
      ),
    );
  }
}
