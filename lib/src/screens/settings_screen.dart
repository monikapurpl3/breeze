import 'package:flutter/material.dart';

import '../app_scope.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

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
            subtitle: Text(server),
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
            title: Text('Change server', style: TextStyle(color: scheme.error)),
            subtitle: const Text('Forget this server, key and token; start over'),
            onTap: () async {
              if (await _confirm(context, 'Change server?',
                  'This erases the stored server address, access key and device token.')) {
                if (!context.mounted) return;
                final nav = Navigator.of(context);
                await c.changeServer();
                nav.popUntil((r) => r.isFirst);
              }
            },
          ),
          const Divider(),
          const AboutListTile(
            icon: Icon(Icons.info_outline),
            applicationName: 'Breeze',
            applicationVersion: '2.0.0',
            aboutBoxChildren: [
              Text('A climate control client. Material You dynamic colour, '
                  'light/dark following your system (or forced in Settings). '
                  'Requests are signed per-device with an Ed25519 key that '
                  'never leaves the phone; the access key and key material are '
                  'stored encrypted and traffic is over HTTPS.'),
            ],
          ),
        ],
      ),
    );
  }
}
