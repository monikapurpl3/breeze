// The Nerd screen's second tab: internal settings. Nothing here is needed to
// use the app; it is for bending it to an unusual setup, and for seeing what
// it is doing. Per-app settings live in InternalPrefs; per-server ones (the
// fallback addresses, a pinned auth version) in that server's profile.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../api_client.dart';
import '../app_scope.dart';
import '../haptics.dart';
import '../internal_prefs.dart';
import '../widgets/loading_cat.dart';
import 'json_view_screen.dart';

class InternalTab extends StatefulWidget {
  const InternalTab({super.key});

  @override
  State<InternalTab> createState() => _InternalTabState();
}

class _InternalTabState extends State<InternalTab> {
  // This server's profile, read once and kept in step with every change.
  List<String> _fallbacks = [];
  bool _lan = false;
  List<String> _lanAddresses = [];
  String? _lanNote;
  bool _learning = false;
  int? _authVersion;
  String _label = '';
  bool _loaded = false;

  late final TextEditingController _facts;
  bool _factsDirty = false;

  @override
  void initState() {
    super.initState();
    _facts = TextEditingController();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    _facts.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final c = AppScope.of(context);
    final s = c.store;
    final fallbacks = await s.fallbackUrls;
    final lan = await s.lanFallback;
    final lanAddresses = await s.lanAddresses;
    final av = await s.authVersion;
    final label = await s.deviceLabel ?? c.deviceLabel;
    if (!mounted) return;
    setState(() {
      _fallbacks = fallbacks;
      _lan = lan;
      _lanAddresses = lanAddresses;
      _authVersion = av;
      _label = label;
      _facts.text = c.internal.catFacts.join('\n');
      _loaded = true;
    });
  }

  void _snack(String m) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

  @override
  Widget build(BuildContext context) {
    if (!_loaded) return const Center(child: CircularProgressIndicator());
    final c = AppScope.of(context);
    final i = c.internal;
    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 40),
      children: [
        _Card(
          title: 'Colours',
          icon: Icons.palette_outlined,
          children: [
            SegmentedButton<ColourSource>(
              segments: const [
                ButtonSegment(
                  value: ColourSource.wallpaper,
                  label: Text('Material You'),
                  icon: Icon(Icons.wallpaper),
                ),
                ButtonSegment(
                  value: ColourSource.custom,
                  label: Text('My colour'),
                  icon: Icon(Icons.colorize),
                ),
              ],
              selected: {i.colourSource},
              onSelectionChanged: (s) =>
                  c.updateInternal((p) => p.colourSource = s.first),
            ),
            const SizedBox(height: 6),
            Text(
              i.colourSource == ColourSource.wallpaper
                  ? 'From the wallpaper, where the system offers it (Android 12 and '
                      'newer); the built-in teal elsewhere.'
                  : 'Your colour, everywhere, whatever the wallpaper.',
              style: _hint(context),
            ),
            if (i.colourSource == ColourSource.custom) ...[
              const SizedBox(height: 12),
              _Swatches(
                selected: i.seedColour,
                onPick: (v) => c.updateInternal((p) => p.seedColour = v),
              ),
              const SizedBox(height: 8),
              _HexField(
                value: i.seedColour,
                onSubmit: (v) => c.updateInternal((p) => p.seedColour = v),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<DynamicSchemeVariant>(
                initialValue: i.schemeVariant,
                decoration: const InputDecoration(
                  labelText: 'Style',
                  border: OutlineInputBorder(),
                ),
                items: [
                  for (final v in _variants.entries)
                    DropdownMenuItem(value: v.key, child: Text(v.value)),
                ],
                onChanged: (v) {
                  if (v != null) c.updateInternal((p) => p.schemeVariant = v);
                },
              ),
            ],
            const SizedBox(height: 12),
            const _SchemePreview(),
          ],
        ),
        _Card(
          title: 'Connection',
          icon: Icons.lan_outlined,
          children: _connection(c),
        ),
        _Card(
          title: 'Pairing',
          icon: Icons.verified_user_outlined,
          children: [
            _Fact('This device', _label),
            _Fact(
              'Signs in with',
              _authVersion == null
                  ? '?'
                  : _authVersion! >= 2
                      ? 'v2 (Ed25519-signed requests)'
                      : 'v1 (a bearer token)',
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              icon: const Icon(Icons.link),
              label: const Text('Pair again…'),
              onPressed: _pairAgain,
            ),
            const SizedBox(height: 4),
            Text(
              'Asks for a new pairing code, with a name and auth version you '
              'choose. This device keeps working as it is until an admin '
              'approves the new code.',
              style: _hint(context),
            ),
          ],
        ),
        _Card(
          title: 'Display and feel',
          icon: Icons.tune,
          children: [
            _Switch(
              'Show each unit\'s IP address',
              'Under its name on the control screen',
              i.showUnitIp,
              (v) => c.updateInternal((p) => p.showUnitIp = v),
            ),
            _Switch(
              'Show latency at the top',
              'Round-trip time to the server, measured every 15 seconds, and '
                  'the address in use when a fallback is answering',
              i.showLatency,
              (v) => c.updateInternal((p) => p.showLatency = v),
            ),
            _Switch(
              'Vibration',
              'The small taps and buzzes that confirm a control',
              i.haptics,
              (v) => c.updateInternal((p) => p.haptics = v),
            ),
          ],
        ),
        _Card(
          title: 'What the server holds',
          icon: Icons.data_object,
          children: [
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.event_note_outlined),
              title: const Text('Programs, as JSON'),
              subtitle: const Text('Favourites, schedules and curves. Read-only'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => _openJson(
                'Programs',
                () => c.api!.programsRaw(),
                kinds: const ['favourite', 'schedule', 'curve'],
              ),
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.hourglass_empty),
              title: const Text('Timers, as JSON'),
              subtitle: const Text('Sleep timers and scheduled starts. Read-only'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => _openJson(
                'Timers',
                () => c.api!.timersRaw(withStarts: true),
              ),
            ),
          ],
        ),
        _Card(
          title: 'Cat facts',
          icon: Icons.pets,
          children: [
            Text('Your own, one per line, shown while the app waits on the server.',
                style: _hint(context)),
            const SizedBox(height: 8),
            TextField(
              controller: _facts,
              minLines: 3,
              maxLines: 8,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'Cat facts',
                hintText: 'A cat\'s purr is around 25 to 150 hertz.',
                border: OutlineInputBorder(),
              ),
              onChanged: (_) => setState(() => _factsDirty = true),
            ),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: _factsDirty ? _saveFacts : null,
                child: const Text('Save facts'),
              ),
            ),
            _Switch(
              'Keep the built-in facts too',
              '${CatFacts.all.length} of them, mixed in with yours',
              i.builtInCatFacts,
              (v) => c.updateInternal((p) => p.builtInCatFacts = v),
            ),
            const SizedBox(height: 4),
            Text('Next up: “${CatFacts.random()}”', style: _hint(context)),
          ],
        ),
        const SizedBox(height: 8),
        Center(
          child: TextButton.icon(
            icon: const Icon(Icons.restart_alt),
            label: const Text('Reset these settings'),
            onPressed: _reset,
          ),
        ),
      ],
    );
  }

  // --- connection ------------------------------------------------------------

  List<Widget> _connection(dynamic c) {
    final api = c.api as ApiClient?;
    final i = c.internal as InternalPrefs;
    return [
      _Fact('Main address', api?.baseUrl ?? '?'),
      if (api != null)
        ListenableBuilder(
          listenable: Listenable.merge([api.currentUrl, api.latencyMs]),
          builder: (context, _) => _Fact(
            'In use now',
            '${api.currentUrl.value}'
                '${api.latencyMs.value == null ? '' : ' · ${api.latencyMs.value} ms'}',
          ),
        ),
      const SizedBox(height: 10),
      Text('Fallback addresses', style: Theme.of(context).textTheme.titleSmall),
      const SizedBox(height: 2),
      Text(
        'Tried in this order when the main address can\'t be reached, then the '
        'LAN addresses below. This device\'s pairing works at all of them.',
        style: _hint(context),
      ),
      const SizedBox(height: 6),
      for (var n = 0; n < _fallbacks.length; n++)
        _FallbackRow(
          url: _fallbacks[n],
          position: n + 1,
          onUp: n == 0 ? null : () => _moveFallback(n, n - 1),
          onDown: n == _fallbacks.length - 1 ? null : () => _moveFallback(n, n + 1),
          onRemove: () => _setFallbacks([..._fallbacks]..removeAt(n)),
        ),
      Align(
        alignment: Alignment.centerLeft,
        child: TextButton.icon(
          icon: const Icon(Icons.add),
          label: const Text('Add a fallback address'),
          onPressed: _addFallback,
        ),
      ),
      const Divider(height: 20),
      _Switch(
        'Then try the server\'s LAN addresses',
        'Asked from the server and refreshed at every launch: for when the '
            'main address is a public one and you are at home',
        _lan,
        (v) async {
          setState(() {
            _lan = v;
            _learning = v;
            _lanNote = null;
          });
          await c.setLanFallback(v);
          await _refreshLan();
        },
      ),
      if (_lan) ...[
        if (_learning)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 6),
            child: LinearProgressIndicator(),
          )
        else if (_lanAddresses.isEmpty)
          Text(_lanNote ?? 'None learned yet.', style: _hint(context))
        else
          for (final a in _lanAddresses) _Fact('LAN', a),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            icon: const Icon(Icons.refresh),
            label: const Text('Ask the server again'),
            onPressed: _learning ? null : _learnLan,
          ),
        ),
      ],
      const Divider(height: 20),
      Text('Give up on a request after ${i.timeoutSeconds} s',
          style: Theme.of(context).textTheme.titleSmall),
      Slider(
        min: InternalPrefs.minTimeoutSeconds.toDouble(),
        max: InternalPrefs.maxTimeoutSeconds.toDouble(),
        divisions: InternalPrefs.maxTimeoutSeconds - InternalPrefs.minTimeoutSeconds,
        value: i.timeoutSeconds.toDouble(),
        label: '${i.timeoutSeconds} s',
        semanticFormatterCallback: (v) => '${v.round()} seconds',
        onChanged: (v) => c.updateInternal((p) => p.timeoutSeconds = v.round()),
      ),
      Text(
        'Per address. With fallbacks, a short timeout reaches the next one sooner.',
        style: _hint(context),
      ),
      const SizedBox(height: 6),
      _Switch(
        'Live updates',
        'Changes pushed by the server as they happen. Off: ask every 5 seconds '
            'instead, as with a server older than 3.0',
        i.liveUpdates,
        (v) => c.updateInternal((p) => p.liveUpdates = v),
      ),
    ];
  }

  Future<void> _setFallbacks(List<String> urls) async {
    final c = AppScope.of(context);
    await c.setFallbackUrls(urls);
    final saved = await c.store.fallbackUrls;
    if (mounted) setState(() => _fallbacks = saved);
  }

  void _moveFallback(int from, int to) {
    final list = [..._fallbacks];
    final u = list.removeAt(from);
    list.insert(to, u);
    Haptics.tick();
    _setFallbacks(list);
  }

  Future<void> _addFallback() async {
    final ctrl = TextEditingController();
    final url = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Fallback address'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          keyboardType: TextInputType.url,
          decoration: const InputDecoration(
            labelText: 'Address',
            hintText: 'https://breeze.example.com or 192.168.1.10:8420',
          ),
          onSubmitted: (v) => Navigator.pop(ctx, v),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text),
            child: const Text('Add'),
          ),
        ],
      ),
    );
    ctrl.dispose();
    if (url == null || url.trim().isEmpty || !mounted) return;
    final normal = ApiClient.normalizeUrl(url);
    if (normal == AppScope.of(context).api?.baseUrl) {
      _snack('That is the main address already.');
      return;
    }
    await _setFallbacks([..._fallbacks, normal]);
  }

  Future<void> _learnLan() async {
    setState(() {
      _learning = true;
      _lanNote = null;
    });
    String? note;
    try {
      note = await AppScope.of(context).learnLanAddresses();
    } on ApiException catch (e) {
      note = e.status == 404
          ? 'This server can\'t say: it needs Breeze Core 3.0.5 or newer.'
          : 'Could not ask the server: ${e.message}';
    } catch (e) {
      note = 'Could not ask the server: $e';
    }
    _lanNote = note;
    await _refreshLan();
  }

  Future<void> _refreshLan() async {
    final addresses = await AppScope.of(context).store.lanAddresses;
    if (mounted) {
      setState(() {
        _lanAddresses = addresses;
        _learning = false;
      });
    }
  }

  // --- pairing ---------------------------------------------------------------

  Future<void> _pairAgain() async {
    final c = AppScope.of(context);
    final choice = await showDialog<(int, String)>(
      context: context,
      builder: (_) => _PairAgainDialog(label: _label, authVersion: _authVersion ?? 2),
    );
    if (choice == null || !mounted) return;
    final (version, name) = choice;
    final nav = Navigator.of(context);
    try {
      await c.pairAgain(authVersion: version, label: name);
      // The pairing screen replaces the home screen underneath; close the
      // Nerd screen so it is what you see.
      nav.popUntil((r) => r.isFirst);
    } on ApiException catch (e) {
      _snack(e.status == 426
          ? 'This server only accepts v2 pairing.'
          : 'Could not start pairing: ${e.message}');
    } catch (e) {
      _snack('Could not start pairing: $e');
    }
  }

  // --- the rest --------------------------------------------------------------

  Future<void> _saveFacts() async {
    final facts = _facts.text
        .split('\n')
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .toList();
    await AppScope.of(context).updateInternal((p) => p.catFacts = facts);
    if (!mounted) return;
    setState(() => _factsDirty = false);
    _snack(facts.isEmpty
        ? 'No facts of your own: the built-in ones it is'
        : '${facts.length} ${facts.length == 1 ? 'fact' : 'facts'} saved');
  }

  Future<void> _reset() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Reset these settings?'),
        content: const Text(
          'Colours, display, vibration, timeout, live updates and cat facts go '
          'back to how the app ships. Fallback addresses and pairing are this '
          'server\'s, and stay.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Reset')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    await AppScope.of(context).resetInternal();
    if (!mounted) return;
    setState(() {
      _facts.text = '';
      _factsDirty = false;
    });
  }

  Future<void> _openJson(
    String title,
    Future<List<dynamic>> Function() load, {
    List<String> kinds = const [],
  }) =>
      Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => JsonViewScreen(title: title, load: load, kinds: kinds),
      ));
}

TextStyle? _hint(BuildContext context) => Theme.of(context)
    .textTheme
    .bodySmall
    ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant);

const _variants = {
  DynamicSchemeVariant.tonalSpot: 'Calm (the default)',
  DynamicSchemeVariant.vibrant: 'Vibrant',
  DynamicSchemeVariant.expressive: 'Expressive',
  DynamicSchemeVariant.content: 'Faithful to the colour',
  DynamicSchemeVariant.fidelity: 'True to the colour',
  DynamicSchemeVariant.rainbow: 'Rainbow',
  DynamicSchemeVariant.fruitSalad: 'Fruit salad',
  DynamicSchemeVariant.neutral: 'Muted',
  DynamicSchemeVariant.monochrome: 'Monochrome',
};

// --- pieces -------------------------------------------------------------------

class _Card extends StatelessWidget {
  const _Card({required this.title, required this.icon, required this.children});
  final String title;
  final IconData icon;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    // The program editor's look: a quiet outlined surface, and a Material so
    // the switches' ripples show.
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Material(
        color: scheme.surfaceContainerLow,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.5)),
        ),
        child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Semantics(
              header: true,
              child: Row(
                children: [
                  Icon(icon, size: 18, color: scheme.primary),
                  const SizedBox(width: 8),
                  Text(
                    title.toUpperCase(),
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: scheme.primary,
                          letterSpacing: 1.2,
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            ...children,
          ],
        ),
      ),
      ),
    );
  }
}

class _Fact extends StatelessWidget {
  const _Fact(this.label, this.value);
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 110,
            child: Text(label,
                style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 13)),
          ),
          Expanded(
            child: Text(value, style: const TextStyle(fontSize: 13)),
          ),
        ],
      ),
    );
  }
}

class _Switch extends StatelessWidget {
  const _Switch(this.title, this.subtitle, this.value, this.onChanged);
  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) => SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: Text(title),
        subtitle: Text(subtitle),
        value: value,
        onChanged: onChanged,
      );
}

class _FallbackRow extends StatelessWidget {
  const _FallbackRow({
    required this.url,
    required this.position,
    required this.onUp,
    required this.onDown,
    required this.onRemove,
  });

  final String url;
  final int position;
  final VoidCallback? onUp;
  final VoidCallback? onDown;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 3),
      padding: const EdgeInsets.only(left: 10),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Text('$position', style: TextStyle(color: scheme.primary, fontWeight: FontWeight.w700)),
          const SizedBox(width: 10),
          Expanded(
            child: Text(url,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 13)),
          ),
          IconButton(
            tooltip: 'Try $url earlier',
            icon: const Icon(Icons.arrow_upward),
            onPressed: onUp,
          ),
          IconButton(
            tooltip: 'Try $url later',
            icon: const Icon(Icons.arrow_downward),
            onPressed: onDown,
          ),
          IconButton(
            tooltip: 'Remove $url',
            icon: const Icon(Icons.close),
            onPressed: onRemove,
          ),
        ],
      ),
    );
  }
}

/// A row of colours to start from. Each is a button that says its name and
/// whether it is the one in use.
class _Swatches extends StatelessWidget {
  const _Swatches({required this.selected, required this.onPick});
  final int selected;
  final ValueChanged<int> onPick;

  static const _colours = <int, String>{
    0xFF4FD1C5: 'Teal',
    0xFF4D97EA: 'Blue',
    0xFF5C6BC0: 'Indigo',
    0xFF9D7CD8: 'Lavender',
    0xFFE0507C: 'Pink',
    0xFFE2504A: 'Red',
    0xFFF0954B: 'Orange',
    0xFFE0B93A: 'Amber',
    0xFF5FC768: 'Green',
    0xFF7F9CB5: 'Slate',
    0xFF8D6E63: 'Brown',
    0xFF9E9E9E: 'Grey',
  };

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        for (final e in _colours.entries)
          Semantics(
            button: true,
            selected: e.key == selected,
            label: e.value,
            excludeSemantics: true,
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: () {
                Haptics.select();
                onPick(e.key);
              },
              child: Container(
                width: 48,
                height: 48,
                padding: const EdgeInsets.all(5),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: Color(e.key),
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: e.key == selected ? scheme.onSurface : Colors.transparent,
                      width: 3,
                    ),
                  ),
                  child: e.key == selected
                      ? const Icon(Icons.check, color: Colors.black87, size: 20)
                      : null,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _HexField extends StatefulWidget {
  const _HexField({required this.value, required this.onSubmit});
  final int value;
  final ValueChanged<int> onSubmit;

  @override
  State<_HexField> createState() => _HexFieldState();
}

class _HexFieldState extends State<_HexField> {
  late final TextEditingController _c = TextEditingController(text: _hex(widget.value));
  String? _error;

  static String _hex(int v) =>
      '#${(v & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase()}';

  @override
  void didUpdateWidget(_HexField old) {
    super.didUpdateWidget(old);
    if (old.value != widget.value) _c.text = _hex(widget.value);
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  void _submit(String raw) {
    final s = raw.trim().replaceFirst('#', '');
    final ok = RegExp(r'^[0-9a-fA-F]{6}$').hasMatch(s);
    setState(() => _error = ok ? null : 'Six hex digits, like #4FD1C5');
    if (ok) widget.onSubmit(0xFF000000 | int.parse(s, radix: 16));
  }

  @override
  Widget build(BuildContext context) => TextField(
        controller: _c,
        decoration: InputDecoration(
          labelText: 'Or any colour',
          border: const OutlineInputBorder(),
          errorText: _error,
          suffixIcon: IconButton(
            tooltip: 'Use this colour',
            icon: const Icon(Icons.check),
            onPressed: () => _submit(_c.text),
          ),
        ),
        inputFormatters: [
          FilteringTextInputFormatter.allow(RegExp(r'[#0-9a-fA-F]')),
          LengthLimitingTextInputFormatter(7),
        ],
        onSubmitted: _submit,
      );
}

/// The scheme in use, as six chips, so a change is visible at once.
class _SchemePreview extends StatelessWidget {
  const _SchemePreview();

  @override
  Widget build(BuildContext context) {
    final s = Theme.of(context).colorScheme;
    final pairs = [
      ('Primary', s.primary, s.onPrimary),
      ('Secondary', s.secondary, s.onSecondary),
      ('Tertiary', s.tertiary, s.onTertiary),
      ('Container', s.primaryContainer, s.onPrimaryContainer),
      ('Surface', s.surfaceContainerHighest, s.onSurface),
      ('Error', s.error, s.onError),
    ];
    return ExcludeSemantics(
      child: Wrap(
        spacing: 6,
        runSpacing: 6,
        children: [
          for (final (name, bg, fg) in pairs)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(8)),
              child: Text(name, style: TextStyle(color: fg, fontSize: 12)),
            ),
        ],
      ),
    );
  }
}

class _PairAgainDialog extends StatefulWidget {
  const _PairAgainDialog({required this.label, required this.authVersion});
  final String label;
  final int authVersion;

  @override
  State<_PairAgainDialog> createState() => _PairAgainDialogState();
}

class _PairAgainDialogState extends State<_PairAgainDialog> {
  late final TextEditingController _name = TextEditingController(text: widget.label);
  late int _version = widget.authVersion >= 2 ? 2 : 1;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Pair again'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _name,
              decoration: const InputDecoration(
                labelText: 'Name for this device',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 14),
            SegmentedButton<int>(
              segments: const [
                ButtonSegment(value: 2, label: Text('v2, signed')),
                ButtonSegment(value: 1, label: Text('v1, token')),
              ],
              selected: {_version},
              onSelectionChanged: (s) => setState(() => _version = s.first),
            ),
            const SizedBox(height: 8),
            Text(
              _version == 2
                  ? 'Every request is signed with a key that never leaves this '
                      'phone. What the app uses normally.'
                  : 'A bearer token, as before 3.0. For testing a server with v1; '
                      'the app stays on v1 instead of upgrading itself.',
              style: _hint(context),
            ),
            const SizedBox(height: 8),
            Text(
              'An admin approves the new code on the server\'s network. Until '
              'then this device works as it does now; its old entry stays in the '
              'server\'s device list until revoked there.',
              style: _hint(context),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(
          onPressed: () => Navigator.pop(context, (_version, _name.text)),
          child: const Text('Get a code'),
        ),
      ],
    );
  }
}
