// Switch between saved servers, add another, forget one.
//
// The point of this screen is that switching costs nothing: each server's
// credential stays in the keystore, so going back to one you've used before
// is instant. Re-pairing would mean getting an admin onto *that* server's LAN
// to approve a code — fine once, miserable every time you move between a home
// and an office.

import 'package:material_ui/material_ui.dart';

import '../app_controller.dart';
import '../app_scope.dart';
import '../haptics.dart';
import '../l10n.dart';
import '../secure_store.dart';

/// Back to the screen this was opened from, unless the app has just changed
/// stage - then all the way to the root.
///
/// Onboarding, pairing and home are not routes: they are what the root route
/// shows, chosen by AppController.stage. This screen is opened from Settings,
/// which is itself pushed on top of that root, so popping only this one
/// leaves Settings covering whatever the root now shows. That is how "Add a
/// server" used to drop you back into Settings, with the add-a-server screen
/// appearing only once Settings was closed.
void _leave(NavigatorState nav, AppController c) {
  if (c.stage == AppStage.home) {
    if (nav.canPop()) nav.pop();
  } else {
    nav.popUntil((r) => r.isFirst);
  }
}

class ServersScreen extends StatelessWidget {
  const ServersScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final c = AppScope.of(context);
    final scheme = Theme.of(context).colorScheme;
    final profiles = c.profiles;
    final l = context.l10n;

    return Scaffold(
      appBar: AppBar(title: Text(l.serversTitle)),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 24),
        children: [
          if (profiles.isEmpty)
            Padding(
              padding: const EdgeInsets.all(24),
              child: Text(l.serversEmpty),
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
                // Home: back to Settings, now showing the new server. A
                // server that needs pairing again: to the pairing screen.
                _leave(nav, c);
              },
              onRename: () => _rename(context, p),
              onForget: () => _forget(context, p),
            ),
          const Divider(height: 24),
          ListTile(
            leading: Icon(Icons.add_circle_outline, color: scheme.primary),
            title: Text(l.serversAdd),
            subtitle: Text(l.serversAddHint),
            onTap: () {
              Haptics.tick();
              // Settings as well as this screen, or onboarding opens under it.
              Navigator.of(context).popUntil((r) => r.isFirst);
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
        title: Text(ctx.l10n.serversRenameTitle),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: InputDecoration(
            labelText: ctx.l10n.serversName,
            helperText: ctx.l10n.serversNameHelper,
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(ctx.l10n.actionCancel)),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: Text(ctx.l10n.actionSave),
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
        title: Text(ctx.l10n.serversForgetTitle(p.name)),
        content: Text(ctx.l10n.serversForgetBody),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(ctx.l10n.actionCancel)),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(ctx.l10n.serversForget),
          ),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    Haptics.failure();
    final nav = Navigator.of(context);
    await c.removeProfile(p.id);
    // Forgetting the active server switches to another, which may need
    // pairing again, and forgetting the last one returns to onboarding. Both
    // happen on the root, so clear the whole stack for them; otherwise stay
    // here with the shorter list.
    if (c.stage != AppStage.home || c.profiles.isEmpty) {
      nav.popUntil((r) => r.isFirst);
    }
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
    final l = context.l10n;
    return ListTile(
      leading: Icon(
        active ? Icons.check_circle : Icons.dns_outlined,
        color: active ? scheme.primary : scheme.onSurfaceVariant,
      ),
      title: Text(profile.name,
          style: TextStyle(fontWeight: active ? FontWeight.w600 : FontWeight.normal)),
      subtitle: Text(
        '${profile.url}\n'
        '${l.serversDetail(profile.hasCredential ? l.serversPaired : l.serversNotPaired, profile.authVersion, profile.label)}',
      ),
      isThreeLine: true,
      onTap: onTap,
      trailing: PopupMenuButton<String>(
        onSelected: (v) => v == 'rename' ? onRename() : onForget(),
        itemBuilder: (_) => [
          PopupMenuItem(value: 'rename', child: Text(l.actionRename)),
          PopupMenuItem(value: 'forget', child: Text(l.serversForget)),
        ],
      ),
    );
  }
}
