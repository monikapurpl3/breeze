// The Nerd screen's second tab: internal settings. Nothing here is needed to
// use the app; it is for bending it to an unusual setup, and for seeing what
// it is doing. Per-app settings live in InternalPrefs; per-server ones (the
// fallback addresses, a pinned auth version) in that server's profile.

import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';

import '../api_client.dart';
import '../app_scope.dart';
import '../haptics.dart';
import '../internal_prefs.dart';
import '../l10n.dart';
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
    final l = context.l10n;
    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 40),
      children: [
        _Card(
          title: l.internalColours,
          icon: Icons.palette_outlined,
          children: [
            SegmentedButton<ColourSource>(
              segments: [
                const ButtonSegment(
                  value: ColourSource.wallpaper,
                  label: Text('Material You'),
                  icon: Icon(Icons.wallpaper),
                ),
                ButtonSegment(
                  value: ColourSource.custom,
                  label: Text(l.internalColourSourceMine),
                  icon: const Icon(Icons.colorize),
                ),
              ],
              selected: {i.colourSource},
              onSelectionChanged: (s) =>
                  c.updateInternal((p) => p.colourSource = s.first),
            ),
            const SizedBox(height: 6),
            Text(
              i.colourSource == ColourSource.wallpaper
                  ? l.internalColourWallpaperHint
                  : l.internalColourMineHint,
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
                decoration: InputDecoration(
                  labelText: l.internalColourStyle,
                  border: const OutlineInputBorder(),
                ),
                items: [
                  for (final v in _variants(l).entries)
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
          title: l.internalConnection,
          icon: Icons.lan_outlined,
          children: _connection(c),
        ),
        _Card(
          title: l.internalPairing,
          icon: Icons.verified_user_outlined,
          children: [
            _Fact(l.internalThisDevice, _label),
            _Fact(
              l.internalSignsInWith,
              _authVersion == null
                  ? '?'
                  : _authVersion! >= 2
                      ? l.internalAuthV2
                      : l.internalAuthV1,
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              icon: const Icon(Icons.link),
              label: Text(l.internalPairAgainButton),
              onPressed: _pairAgain,
            ),
            const SizedBox(height: 4),
            Text(
              l.internalPairAgainHint,
              style: _hint(context),
            ),
          ],
        ),
        _Card(
          title: l.internalDisplay,
          icon: Icons.tune,
          children: [
            _Switch(
              l.internalShowIp,
              l.internalShowIpHint,
              i.showUnitIp,
              (v) => c.updateInternal((p) => p.showUnitIp = v),
            ),
            _Switch(
              l.internalShowLatency,
              l.internalShowLatencyHint,
              i.showLatency,
              (v) => c.updateInternal((p) => p.showLatency = v),
            ),
            _Switch(
              l.internalVibration,
              l.internalVibrationHint,
              i.haptics,
              (v) => c.updateInternal((p) => p.haptics = v),
            ),
          ],
        ),
        _Card(
          title: l.internalServerData,
          icon: Icons.data_object,
          children: [
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.event_note_outlined),
              title: Text(l.internalProgramsJson),
              subtitle: Text(l.internalProgramsJsonHint),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => _openJson(
                l.internalProgramsTitle,
                () => c.api!.programsRaw(),
                kinds: const ['favourite', 'schedule', 'curve'],
              ),
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.hourglass_empty),
              title: Text(l.internalTimersJson),
              subtitle: Text(l.internalTimersJsonHint),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => _openJson(
                l.internalTimersTitle,
                () => c.api!.timersRaw(withStarts: true),
              ),
            ),
          ],
        ),
        _Card(
          title: l.internalCatFacts,
          icon: Icons.pets,
          children: [
            Text(l.internalCatFactsHint,
                style: _hint(context)),
            const SizedBox(height: 8),
            TextField(
              controller: _facts,
              minLines: 3,
              maxLines: 8,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(
                labelText: l.internalCatFacts,
                hintText: l.internalCatFactsExample,
                border: const OutlineInputBorder(),
              ),
              onChanged: (_) => setState(() => _factsDirty = true),
            ),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: _factsDirty ? _saveFacts : null,
                child: Text(l.internalSaveFacts),
              ),
            ),
            _Switch(
              l.internalKeepBuiltIn,
              l.internalKeepBuiltInHint(CatFacts.all.length),
              i.builtInCatFacts,
              (v) => c.updateInternal((p) => p.builtInCatFacts = v),
            ),
            const SizedBox(height: 4),
            Text(l.internalNextUp(CatFacts.random()), style: _hint(context)),
          ],
        ),
        const SizedBox(height: 8),
        Center(
          child: TextButton.icon(
            icon: const Icon(Icons.restart_alt),
            label: Text(l.internalReset),
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
    final l = context.l10n;
    return [
      _Fact(l.internalMainAddress, api?.baseUrl ?? '?'),
      if (api != null)
        ListenableBuilder(
          listenable: Listenable.merge([api.currentUrl, api.latencyMs]),
          builder: (context, _) => _Fact(
            l.internalInUseNow,
            '${api.currentUrl.value}'
                '${api.latencyMs.value == null ? '' : ' · ${api.latencyMs.value} ms'}',
          ),
        ),
      const SizedBox(height: 10),
      Text(l.internalFallbacks, style: Theme.of(context).textTheme.titleSmall),
      const SizedBox(height: 2),
      Text(
        l.internalFallbacksHint,
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
          label: Text(l.internalAddFallback),
          onPressed: _addFallback,
        ),
      ),
      const Divider(height: 20),
      _Switch(
        l.internalTryLan,
        l.internalTryLanHint,
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
          Text(_lanNote ?? l.internalLanNoneYet, style: _hint(context))
        else
          for (final a in _lanAddresses) _Fact('LAN', a),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            icon: const Icon(Icons.refresh),
            label: Text(l.internalAskAgain),
            onPressed: _learning ? null : _learnLan,
          ),
        ),
      ],
      const Divider(height: 20),
      Text(l.internalTimeout(i.timeoutSeconds),
          style: Theme.of(context).textTheme.titleSmall),
      Slider(
        min: InternalPrefs.minTimeoutSeconds.toDouble(),
        max: InternalPrefs.maxTimeoutSeconds.toDouble(),
        divisions: InternalPrefs.maxTimeoutSeconds - InternalPrefs.minTimeoutSeconds,
        value: i.timeoutSeconds.toDouble(),
        label: '${i.timeoutSeconds} s',
        semanticFormatterCallback: (v) => l.internalTimeoutSemantics(v.round()),
        onChanged: (v) => c.updateInternal((p) => p.timeoutSeconds = v.round()),
      ),
      Text(
        l.internalTimeoutHint,
        style: _hint(context),
      ),
      const SizedBox(height: 6),
      _Switch(
        l.internalLiveUpdates,
        l.internalLiveUpdatesHint('3.0'),
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
    final l = context.l10n;
    final ctrl = TextEditingController();
    final url = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l.internalFallbackDialogTitle),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          keyboardType: TextInputType.url,
          decoration: InputDecoration(
            labelText: l.internalAddressLabel,
            hintText: l.internalAddressHint,
          ),
          onSubmitted: (v) => Navigator.pop(ctx, v),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(l.actionCancel)),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text),
            child: Text(l.actionAdd),
          ),
        ],
      ),
    );
    ctrl.dispose();
    if (url == null || url.trim().isEmpty || !mounted) return;
    final normal = ApiClient.normalizeUrl(url);
    if (normal == AppScope.of(context).api?.baseUrl) {
      _snack(l.internalAlreadyMain);
      return;
    }
    await _setFallbacks([..._fallbacks, normal]);
  }

  Future<void> _learnLan() async {
    final l = context.l10n;
    setState(() {
      _learning = true;
      _lanNote = null;
    });
    String? note;
    try {
      note = await AppScope.of(context).learnLanAddresses(l);
    } on ApiException catch (e) {
      note = e.status == 404
          ? l.internalLanNeedsNewer('3.0.5')
          : l.internalLanAskFailed(e.message);
    } catch (e) {
      note = l.internalLanAskFailed('$e');
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
    final l = context.l10n;
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
          ? l.internalOnlyV2
          : l.internalPairFailed(e.message));
    } catch (e) {
      _snack(l.internalPairFailed('$e'));
    }
  }

  // --- the rest --------------------------------------------------------------

  Future<void> _saveFacts() async {
    final l = context.l10n;
    final facts = _facts.text
        .split('\n')
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .toList();
    await AppScope.of(context).updateInternal((p) => p.catFacts = facts);
    if (!mounted) return;
    setState(() => _factsDirty = false);
    _snack(facts.isEmpty
        ? l.internalFactsNone
        : l.internalFactsSaved(facts.length));
  }

  Future<void> _reset() async {
    final l = context.l10n;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l.internalResetTitle),
        content: Text(
          l.internalResetBody,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(l.actionCancel)),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(l.internalResetConfirm)),
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

Map<DynamicSchemeVariant, String> _variants(AppLocalizations l) => {
  DynamicSchemeVariant.tonalSpot: l.internalVariantTonalSpot,
  DynamicSchemeVariant.vibrant: l.internalVariantVibrant,
  DynamicSchemeVariant.expressive: l.internalVariantExpressive,
  DynamicSchemeVariant.content: l.internalVariantContent,
  DynamicSchemeVariant.fidelity: l.internalVariantFidelity,
  DynamicSchemeVariant.rainbow: l.internalVariantRainbow,
  DynamicSchemeVariant.fruitSalad: l.internalVariantFruitSalad,
  DynamicSchemeVariant.neutral: l.internalVariantNeutral,
  DynamicSchemeVariant.monochrome: l.internalVariantMonochrome,
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
    final l = context.l10n;
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
            tooltip: l.internalFallbackEarlier(url),
            icon: const Icon(Icons.arrow_upward),
            onPressed: onUp,
          ),
          IconButton(
            tooltip: l.internalFallbackLater(url),
            icon: const Icon(Icons.arrow_downward),
            onPressed: onDown,
          ),
          IconButton(
            tooltip: l.internalFallbackRemove(url),
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

  static Map<int, String> _colours(AppLocalizations l) => <int, String>{
    0xFF4FD1C5: l.internalSwatchTeal,
    0xFF4D97EA: l.internalSwatchBlue,
    0xFF5C6BC0: l.internalSwatchIndigo,
    0xFF9D7CD8: l.internalSwatchLavender,
    0xFFE0507C: l.internalSwatchPink,
    0xFFE2504A: l.internalSwatchRed,
    0xFFF0954B: l.internalSwatchOrange,
    0xFFE0B93A: l.internalSwatchAmber,
    0xFF5FC768: l.internalSwatchGreen,
    0xFF7F9CB5: l.internalSwatchSlate,
    0xFF8D6E63: l.internalSwatchBrown,
    0xFF9E9E9E: l.internalSwatchGrey,
  };

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        for (final e in _colours(context.l10n).entries)
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
    setState(() => _error = ok ? null : context.l10n.internalHexError);
    if (ok) widget.onSubmit(0xFF000000 | int.parse(s, radix: 16));
  }

  @override
  Widget build(BuildContext context) => TextField(
        controller: _c,
        decoration: InputDecoration(
          labelText: context.l10n.internalHexLabel,
          border: const OutlineInputBorder(),
          errorText: _error,
          suffixIcon: IconButton(
            tooltip: context.l10n.internalHexUse,
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
    final l = context.l10n;
    final pairs = [
      (l.internalPreviewPrimary, s.primary, s.onPrimary),
      (l.internalPreviewSecondary, s.secondary, s.onSecondary),
      (l.internalPreviewTertiary, s.tertiary, s.onTertiary),
      (l.internalPreviewContainer, s.primaryContainer, s.onPrimaryContainer),
      (l.internalPreviewSurface, s.surfaceContainerHighest, s.onSurface),
      (l.internalPreviewError, s.error, s.onError),
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
    final l = context.l10n;
    return AlertDialog(
      title: Text(l.internalPairAgainTitle),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _name,
              decoration: InputDecoration(
                labelText: l.internalDeviceName,
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 14),
            SegmentedButton<int>(
              segments: [
                ButtonSegment(value: 2, label: Text(l.internalSegmentV2)),
                ButtonSegment(value: 1, label: Text(l.internalSegmentV1)),
              ],
              selected: {_version},
              onSelectionChanged: (s) => setState(() => _version = s.first),
            ),
            const SizedBox(height: 8),
            Text(
              _version == 2
                  ? l.internalV2Hint
                  : l.internalV1Hint('3.0'),
              style: _hint(context),
            ),
            const SizedBox(height: 8),
            Text(
              l.internalPairAgainNote,
              style: _hint(context),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text(l.actionCancel)),
        FilledButton(
          onPressed: () => Navigator.pop(context, (_version, _name.text)),
          child: Text(l.internalGetCode),
        ),
      ],
    );
  }
}
