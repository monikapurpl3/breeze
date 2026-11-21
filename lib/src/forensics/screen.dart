// The forensic build's own screen, from the little bug button on every
// screen: the log as it happens, every HTTP exchange, the network probes, a
// snapshot of everything the app holds, and the files written so far. Mark
// puts a line in the log to find a moment later; Export writes one file with
// everything, which the Files app shows under On My iPhone > Breeze Debug.

import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../app_controller.dart';
import '../app_scope.dart';
import 'forensics.dart';
import 'hooks.dart';
import 'http_log.dart';
import 'probes.dart';
import 'snapshot.dart';

const _mono = TextStyle(fontFamily: 'Menlo', fontFamilyFallback: ['Courier', 'monospace'], fontSize: 11.5, height: 1.25);

final ValueNotifier<bool> _open = ValueNotifier(false);

/// The bug button over every screen, with the count of warnings and errors
/// since the screen was last opened. Drag it out of the way; a long press
/// hides it for a minute. It starts at the bottom left, in the row of the
/// home screen's page dots, which is empty there.
class ForensicsOverlay extends StatefulWidget {
  const ForensicsOverlay({super.key, required this.child});
  final Widget child;

  @override
  State<ForensicsOverlay> createState() => _ForensicsOverlayState();
}

class _ForensicsOverlayState extends State<ForensicsOverlay> {
  static const _size = 44.0;
  bool _hidden = false;
  Offset? _pos;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final screen = MediaQuery.sizeOf(context);
    final pad = MediaQuery.paddingOf(context);
    Offset clamp(Offset o) => Offset(
          o.dx.clamp(0.0, (screen.width - _size).clamp(0.0, double.infinity)),
          o.dy.clamp(pad.top, (screen.height - pad.bottom - _size).clamp(pad.top, double.infinity)),
        );
    final pos = clamp(_pos ?? Offset(6, screen.height - pad.bottom - _size - 4));
    return Stack(children: [
      widget.child,
      ValueListenableBuilder<bool>(
        valueListenable: _open,
        builder: (context, open, _) => open || _hidden
            ? const SizedBox.shrink()
            : Positioned(
                left: pos.dx,
                top: pos.dy,
                child: GestureDetector(
                  onPanUpdate: (d) => setState(() => _pos = clamp(pos + d.delta)),
                  child: ValueListenableBuilder<int>(
                  valueListenable: Forensics.I.unseenErrors,
                  builder: (context, unseen, _) {
                    void open() => forensicNavigator.currentState?.push(
                        MaterialPageRoute<void>(builder: (_) => ForensicsScreen(controller: AppScope.of(context))));
                    // A node of its own: without `container` its label merged
                    // into the screen beneath, and a screen reader read the
                    // button as part of the page.
                    return Semantics(
                    container: true,
                    button: true,
                    label: 'Forensics${unseen > 0 ? ', $unseen new warnings or errors' : ''}',
                    onTap: open,
                    excludeSemantics: true,
                    child: Material(
                      color: unseen > 0 ? scheme.errorContainer : scheme.secondaryContainer.withValues(alpha: 0.85),
                      shape: const CircleBorder(),
                      elevation: 3,
                      child: InkWell(
                        customBorder: const CircleBorder(),
                        onTap: open,
                        onLongPress: () {
                          setState(() => _hidden = true);
                          Timer(const Duration(minutes: 1), () {
                            if (mounted) setState(() => _hidden = false);
                          });
                        },
                        child: SizedBox(
                          width: _size,
                          height: _size,
                          child: Center(
                            child: unseen > 0
                                ? Text(unseen > 99 ? '99+' : '$unseen',
                                    style: TextStyle(color: scheme.onErrorContainer, fontWeight: FontWeight.w700))
                                : Icon(Icons.bug_report, size: 22, color: scheme.onSecondaryContainer),
                          ),
                        ),
                      ),
                    ),
                  );
                  },
                  ),
                ),
              ),
      ),
    ]);
  }
}

class ForensicsScreen extends StatefulWidget {
  const ForensicsScreen({super.key, required this.controller});
  final AppController controller;

  @override
  State<ForensicsScreen> createState() => _ForensicsScreenState();
}

class _ForensicsScreenState extends State<ForensicsScreen> with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 5, vsync: this);
  String _probes = '';
  bool _probing = false;
  String _snapshot = '';
  bool _snapping = false;

  @override
  void initState() {
    super.initState();
    // After this frame: the button listens to these, and is built already.
    scheduleMicrotask(() => _open.value = true);
    Forensics.I.seen();
    flog('forensics', 'screen opened');
  }

  @override
  void dispose() {
    scheduleMicrotask(() => _open.value = false);
    Forensics.I.seen();
    _tabs.dispose();
    super.dispose();
  }

  void _snack(String m) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

  Future<void> _copy(String text, String what) async {
    await Clipboard.setData(ClipboardData(text: text));
    _snack('$what copied (${text.length} characters)');
  }

  Future<void> _mark() async {
    final ctl = TextEditingController();
    final note = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Mark this moment'),
        content: TextField(controller: ctl, autofocus: true, decoration: const InputDecoration(hintText: 'What you are about to do')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, ctl.text), child: const Text('Mark')),
        ],
      ),
    );
    if (note != null) {
      Forensics.I.mark(note.isEmpty ? 'mark' : note);
      _snack('Marked in the log');
    }
  }

  Future<void> _export() async {
    _snack('Exporting: probing the server, reading everything…');
    try {
      final f = await exportBundle(widget.controller);
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Exported'),
          content: Text('${f.uri.pathSegments.last}, ${f.lengthSync() ~/ 1024} KB.\n\n'
              'In the Files app: On My iPhone > Breeze Debug > forensics. From a PC: the Apple Devices app (or iTunes), '
              'Files, Breeze Debug.\n\nIt holds no keys or tokens: those are shown as their length and a fingerprint.'),
          actions: [
            TextButton(onPressed: () => _copy(f.readAsStringSync(), 'The export'), child: const Text('Copy all')),
            FilledButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK')),
          ],
        ),
      );
    } catch (e, st) {
      flog('forensics', 'export failed', level: Level.error, error: e, stack: st);
      _snack('Export failed: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Forensics'),
        actions: [
          IconButton(onPressed: _mark, icon: const Icon(Icons.bookmark_add_outlined), tooltip: 'Mark this moment'),
          IconButton(onPressed: _export, icon: const Icon(Icons.save_alt), tooltip: 'Export everything'),
        ],
        bottom: TabBar(
          controller: _tabs,
          isScrollable: true,
          tabAlignment: TabAlignment.start,
          tabs: const [Tab(text: 'Log'), Tab(text: 'Network'), Tab(text: 'Probes'), Tab(text: 'Snapshot'), Tab(text: 'Files')],
        ),
      ),
      body: TabBarView(controller: _tabs, children: [
        _LogTab(copy: _copy),
        _NetworkTab(copy: _copy),
        _textTab(
          text: _probes,
          busy: _probing,
          button: 'Run the probes',
          hint: 'For every address Breeze would try: DNS, TCP, TLS (and the certificate) and HTTP, timed, each failure explained. '
              'And the phone\'s network: Wi-Fi, cellular, VPN.',
          run: () async {
            setState(() {
              _probing = true;
              _probes = '';
            });
            await runProbes(await probeTargets(widget.controller), live: (l) {
              if (mounted) setState(() => _probes += '$l\n');
            });
            if (mounted) setState(() => _probing = false);
          },
          copyName: 'The probes',
        ),
        _textTab(
          text: _snapshot,
          busy: _snapping,
          button: 'Take a snapshot',
          hint: 'Everything the app holds and the device says, now: preferences, the keychain (never values), files, '
              'the provisioning profile and when it expires, how the last session ended.',
          run: () async {
            setState(() => _snapping = true);
            final s = await snapshot(widget.controller);
            if (mounted) {
              setState(() {
                _snapshot = s;
                _snapping = false;
              });
            }
          },
          copyName: 'The snapshot',
        ),
        _FilesTab(copy: _copy),
      ]),
    );
  }

  Widget _textTab(
      {required String text,
      required bool busy,
      required String button,
      required String hint,
      required Future<void> Function() run,
      required String copyName}) {
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
        child: Text(hint, style: Theme.of(context).textTheme.bodySmall),
      ),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        child: Row(children: [
          FilledButton.icon(onPressed: busy ? null : run, icon: const Icon(Icons.play_arrow), label: Text(button)),
          const SizedBox(width: 8),
          if (text.isNotEmpty) OutlinedButton.icon(onPressed: () => _copy(text, copyName), icon: const Icon(Icons.copy), label: const Text('Copy')),
          if (busy) const Padding(padding: EdgeInsets.only(left: 12), child: SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2))),
        ]),
      ),
      Expanded(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(12, 6, 12, 96),
          child: SelectableText(text, style: _mono),
        ),
      ),
    ]);
  }
}

class _LogTab extends StatefulWidget {
  const _LogTab({required this.copy});
  final Future<void> Function(String, String) copy;

  @override
  State<_LogTab> createState() => _LogTabState();
}

class _LogTabState extends State<_LogTab> {
  Level _min = Level.debug;
  String _filter = '';
  bool _follow = true;
  final _scroll = ScrollController();

  Color _colour(Level l, ColorScheme s) => switch (l) {
        Level.error => s.error,
        Level.warn => Colors.orange.shade700,
        Level.info => s.onSurface,
        Level.debug => s.onSurfaceVariant,
      };

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
        child: Row(children: [
          Expanded(
            child: TextField(
              decoration: const InputDecoration(isDense: true, prefixIcon: Icon(Icons.search), hintText: 'Filter: text or [category]'),
              onChanged: (v) => setState(() => _filter = v.toLowerCase()),
            ),
          ),
          const SizedBox(width: 6),
          DropdownButton<Level>(
            value: _min,
            onChanged: (v) => setState(() => _min = v ?? Level.debug),
            items: const [
              DropdownMenuItem(value: Level.debug, child: Text('all')),
              DropdownMenuItem(value: Level.info, child: Text('info+')),
              DropdownMenuItem(value: Level.warn, child: Text('warn+')),
              DropdownMenuItem(value: Level.error, child: Text('errors')),
            ],
          ),
          IconButton(
            tooltip: _follow ? 'Following new lines' : 'Paused',
            onPressed: () => setState(() => _follow = !_follow),
            icon: Icon(_follow ? Icons.vertical_align_bottom : Icons.pause),
          ),
          IconButton(
            tooltip: 'Copy what is shown',
            onPressed: () => widget.copy(_shown().map((e) => e.line).join('\n'), 'The log'),
            icon: const Icon(Icons.copy),
          ),
        ]),
      ),
      Expanded(
        child: ValueListenableBuilder<int>(
          valueListenable: Forensics.I.changes,
          builder: (context, _, _) {
            final list = _shown();
            if (_follow) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (_scroll.hasClients) _scroll.jumpTo(_scroll.position.maxScrollExtent);
              });
            }
            return ListView.builder(
              controller: _scroll,
              padding: const EdgeInsets.fromLTRB(8, 6, 8, 96),
              itemCount: list.length,
              itemBuilder: (context, i) {
                final e = list[i];
                return InkWell(
                  onTap: () => showDialog<void>(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      content: SingleChildScrollView(child: SelectableText(e.line, style: _mono)),
                      actions: [
                        TextButton(onPressed: () => widget.copy(e.line, 'The line'), child: const Text('Copy')),
                        FilledButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK')),
                      ],
                    ),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 1.5),
                    child: Text(e.line, style: _mono.copyWith(color: _colour(e.level, scheme)), maxLines: 6, overflow: TextOverflow.ellipsis),
                  ),
                );
              },
            );
          },
        ),
      ),
    ]);
  }

  List<Entry> _shown() => Forensics.I.entries
      .where((e) => e.level.index >= _min.index && (_filter.isEmpty || e.line.toLowerCase().contains(_filter)))
      .toList();
}

class _NetworkTab extends StatelessWidget {
  const _NetworkTab({required this.copy});
  final Future<void> Function(String, String) copy;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ValueListenableBuilder<int>(
      valueListenable: HttpRecorder.I.changes,
      builder: (context, _, _) {
        final list = HttpRecorder.I.exchanges.reversed.toList();
        if (list.isEmpty) return const Center(child: Text('No HTTP yet.'));
        return ListView.separated(
          padding: const EdgeInsets.only(bottom: 96),
          itemCount: list.length,
          separatorBuilder: (_, _) => const Divider(height: 1),
          itemBuilder: (context, i) {
            final e = list[i];
            final bad = e.error != null || (e.status ?? 0) >= 400;
            return ListTile(
              dense: true,
              title: Text(e.summary, style: _mono.copyWith(color: bad ? scheme.error : null)),
              subtitle: Text('${e.at.toIso8601String().substring(11, 23)}${e.error == null ? '' : '  ${e.error}'}',
                  maxLines: 2, overflow: TextOverflow.ellipsis),
              onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
                builder: (_) => Scaffold(
                  appBar: AppBar(title: Text('#${e.id}'), actions: [
                    IconButton(onPressed: () => copy(e.detail, 'The exchange'), icon: const Icon(Icons.copy), tooltip: 'Copy'),
                  ]),
                  body: SingleChildScrollView(padding: const EdgeInsets.all(12), child: SelectableText(e.detail, style: _mono)),
                ),
              )),
            );
          },
        );
      },
    );
  }
}

class _FilesTab extends StatefulWidget {
  const _FilesTab({required this.copy});
  final Future<void> Function(String, String) copy;

  @override
  State<_FilesTab> createState() => _FilesTabState();
}

class _FilesTabState extends State<_FilesTab> {
  List<File> _files() {
    final d = Forensics.I.dir;
    if (d == null || !d.existsSync()) return const [];
    return d.listSync().whereType<File>().toList()..sort((a, b) => b.path.compareTo(a.path));
  }

  @override
  Widget build(BuildContext context) {
    final files = _files();
    final d = Forensics.I.dir;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
        child: Text('In the Files app: On My iPhone > Breeze Debug > forensics.\n${d?.path ?? 'not open'}',
            style: Theme.of(context).textTheme.bodySmall),
      ),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Row(children: [
          OutlinedButton.icon(
            onPressed: () async {
              final keep = Forensics.I.sessionFile?.path;
              final ok = await showDialog<bool>(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: const Text('Delete the older files?'),
                  content: const Text('Every log, export and report here except this session\'s log.'),
                  actions: [
                    TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
                    FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Delete')),
                  ],
                ),
              );
              if (ok != true) return;
              for (final f in files) {
                if (f.path != keep && !f.path.endsWith('.state')) {
                  try {
                    f.deleteSync();
                  } catch (_) {}
                }
              }
              flog('forensics', 'older files deleted');
              setState(() {});
            },
            icon: const Icon(Icons.delete_sweep_outlined),
            label: const Text('Delete older'),
          ),
          const SizedBox(width: 8),
          IconButton(onPressed: () => setState(() {}), icon: const Icon(Icons.refresh), tooltip: 'Refresh'),
        ]),
      ),
      Expanded(
        child: ListView(
          padding: const EdgeInsets.only(bottom: 96),
          children: [
            for (final f in files)
              ListTile(
                dense: true,
                title: Text(f.uri.pathSegments.last, style: _mono),
                subtitle: Text('${f.lengthSync()} B, ${f.lastModifiedSync().toIso8601String().substring(0, 19)}'),
                onTap: () {
                  final raw = f.readAsStringSync();
                  // The end of a long file: where it stopped is what matters.
                  final text = raw.length > 400000 ? '… (${raw.length - 400000} characters before)\n${raw.substring(raw.length - 400000)}' : raw;
                  Navigator.of(context).push(MaterialPageRoute<void>(
                    builder: (_) => Scaffold(
                      appBar: AppBar(title: Text(f.uri.pathSegments.last), actions: [
                        IconButton(onPressed: () => widget.copy(raw, 'The file'), icon: const Icon(Icons.copy), tooltip: 'Copy'),
                      ]),
                      body: SingleChildScrollView(padding: const EdgeInsets.all(12), child: SelectableText(text, style: _mono)),
                    ),
                  ));
                },
              ),
          ],
        ),
      ),
    ]);
  }
}
