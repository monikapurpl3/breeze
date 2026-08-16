// Switch between saved servers, add another, forget one.
//
// The point of this screen is that switching costs nothing: each server's
// credential stays in the keystore, so going back to one you've used before
// is instant. Re-pairing would mean getting an admin onto *that* server's LAN
// to approve a code — fine once, miserable every time you move between a home
// and an office.

import 'package:flutter/material.dart';

import '../app_scope.dart';
import '../haptics.dart';
import '../secure_store.dart';

class ServersScreen extends StatelessWidget {
  const ServersScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final c = AppScope.of(context);
    final scheme = Theme.of(context).colorScheme;
    final profiles = c.profiles;

    return Scaffold(
      appBar: AppBar(title: const Text('Servers')),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 24),
        children: [
          if (profiles.isEmpty)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Text('No servers saved yet.'),
            ),
          for (final p in profiles)
            _ServerTile(
              profile: p,
              active: p.id == c.activeProfileId,
              onTap: () async {
                if (p.id == c.activeProfileId) return;
                Haptics.select();
                final nav = Navigator.of(context);
                await c.switchProfile(p.id);
                if (nav.canPop()) nav.pop();
              },
              onRename: () => _rename(context, p),
              onForget: () => _forget(context, p),
            ),
          const Divider(height: 24),
          ListTile(
            leading: Icon(Icons.add_circle_outline, color: scheme.primary),
            title: const Text('Add a server'),
            subtitle: const Text('Pair with another Breeze Core; this one stays saved'),
            onTap: () {
              Haptics.tick();
              Navigator.of(context).pop();
              c.beginAddServer();
            },
          ),
        ],
      ),
    );
  }

  Future<void> _rename(BuildContext context, ServerProfile p) async {
    final c = AppScope.of(context);
    final controller = TextEditingController(text: p.name);
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Rename server'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'Name',
            helperText: 'Just a label on this phone',
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (name == null || name.isEmpty) return;
    await c.store.renameProfile(p.id, name);
    await c.reloadProfiles();
  }

  Future<void> _forget(BuildContext context, ServerProfile p) async {
    final c = AppScope.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Forget ${p.name}?'),
        content: const Text(
          'This phone will erase that server\'s address, access key and device '
          'credential. Pairing again needs an admin on that network.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Forget'),
          ),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    Haptics.failure();
    final nav = Navigator.of(context);
    await c.removeProfile(p.id);
    // Nothing left to manage: close this screen so the app can fall back to
    // onboarding rather than leaving an empty list on top of it.
    if (c.profiles.isEmpty && nav.canPop()) nav.pop();
  }
}

class _ServerTile extends StatelessWidget {
  const _ServerTile({
    required this.profile,
    required this.active,
    required this.onTap,
    required this.onRename,
    required this.onForget,
  });

  final ServerProfile profile;
  final bool active;
  final VoidCallback onTap;
  final VoidCallback onRename;
  final VoidCallback onForget;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ListTile(
      leading: Icon(
        active ? Icons.check_circle : Icons.dns_outlined,
        color: active ? scheme.primary : scheme.onSurfaceVariant,
      ),
      title: Text(profile.name,
          style: TextStyle(fontWeight: active ? FontWeight.w600 : FontWeight.normal)),
      subtitle: Text(
        '${profile.url}\n'
        '${profile.hasCredential ? 'paired' : 'not paired'} · '
        'auth v${profile.authVersion} · as "${profile.label}"',
      ),
      isThreeLine: true,
      onTap: onTap,
      trailing: PopupMenuButton<String>(
        onSelected: (v) => v == 'rename' ? onRename() : onForget(),
        itemBuilder: (_) => const [
          PopupMenuItem(value: 'rename', child: Text('Rename')),
          PopupMenuItem(value: 'forget', child: Text('Forget')),
        ],
      ),
    );
  }
}
