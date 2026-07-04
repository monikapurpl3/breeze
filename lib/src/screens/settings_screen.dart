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
            applicationVersion: '1.0.0',
            aboutBoxChildren: [
              Text('A climate control client. Theme follows your system '
                  '(Material You dynamic colour, light or dark). Access key '
                  'and device token are stored encrypted; traffic is over HTTPS.'),
            ],
          ),
        ],
      ),
    );
  }
}
