// A read-only look at what the server holds, as JSON: the programs
// (favourites, schedules, curves) or the pending timers. Reached from the
// Nerd screen's Internal tab. Nothing here can change anything -- it is for
// seeing exactly what the server has, and copying it into a bug report.

import 'dart:convert';

import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';

import '../api_client.dart';
import '../haptics.dart';
import '../l10n.dart';

class JsonViewScreen extends StatefulWidget {
  const JsonViewScreen({
    super.key,
    required this.title,
    required this.load,
    this.kinds = const [],
  });

  final String title;

  /// Fetches the document. Called on open and on refresh.
  final Future<List<dynamic>> Function() load;

  /// When set, filter chips by each item's `kind` field: the programs view
  /// passes favourite / schedule / curve.
  final List<String> kinds;

  @override
  State<JsonViewScreen> createState() => _JsonViewScreenState();
}

class _JsonViewScreenState extends State<JsonViewScreen> {
  List<dynamic>? _items;
  String? _error;
  bool _loading = true;
  String? _kind; // null = all

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final items = await widget.load();
      if (mounted) setState(() => _items = items);
    } on ApiException catch (e) {
      if (mounted) {
        setState(() => _error = e.status == 404
            ? context.l10n.jsonNotOnServer
            : context.l10n.jsonLoadFailed(e.message));
      }
    } catch (e) {
      if (mounted) setState(() => _error = context.l10n.jsonLoadFailed('$e'));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  List<dynamic> get _shown {
    final items = _items ?? const [];
    if (_kind == null) return items;
    return items.where((e) => e is Map && e['kind'] == _kind).toList();
  }

  String get _text => const JsonEncoder.withIndent('  ').convert(_shown);

  void _copy() {
    Clipboard.setData(ClipboardData(text: _text));
    Haptics.success();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(context.l10n.jsonCopied)),
    );
  }

  /// A filter chip's label: the kind's name, and how many there are. A kind
  /// this app has no name for shows as the server spells it.
  String _kindLabel(AppLocalizations l, String k, int n) => switch (k) {
        'favourite' => l.jsonFilterFavourites(n),
        'schedule' => l.jsonFilterSchedules(n),
        'curve' => l.jsonFilterCurves(n),
        _ => '${k[0].toUpperCase()}${k.substring(1)}s ($n)',
      };

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final l = context.l10n;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        actions: [
          IconButton(
            tooltip: l.jsonCopy,
            icon: const Icon(Icons.copy_all_outlined),
            onPressed: _items == null ? null : _copy,
          ),
          IconButton(
            tooltip: l.nerdRefresh,
            icon: const Icon(Icons.refresh),
            onPressed: _loading ? null : _reload,
          ),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (widget.kinds.isNotEmpty && _items != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
              child: Wrap(
                spacing: 8,
                children: [
                  ChoiceChip(
                    label: Text(l.jsonFilterAll(_items!.length)),
                    selected: _kind == null,
                    onSelected: (_) => setState(() => _kind = null),
                  ),
                  for (final k in widget.kinds)
                    ChoiceChip(
                      label: Text(_kindLabel(l, k,
                          _items!.where((e) => e is Map && e['kind'] == k).length)),
                      selected: _kind == k,
                      onSelected: (_) => setState(() => _kind = k),
                    ),
                ],
              ),
            ),
          Expanded(child: _body(scheme)),
        ],
      ),
    );
  }

  Widget _body(ColorScheme scheme) {
    if (_loading && _items == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Text(_error!, textAlign: TextAlign.center),
        ),
      );
    }
    if (_shown.isEmpty) {
      return Center(
        child: Text(context.l10n.jsonEmpty,
            style: TextStyle(color: scheme.onSurfaceVariant)),
      );
    }
    return Scrollbar(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(12),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: scheme.surfaceContainerHighest.withValues(alpha: 0.5),
            borderRadius: BorderRadius.circular(12),
          ),
          // Long lines scroll sideways rather than wrapping, so the
          // indentation -- which is the structure -- stays readable.
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: SelectableText(
              _text,
              style: TextStyle(
                fontFamily: 'monospace',
                fontSize: 12.5,
                height: 1.35,
                color: scheme.onSurface,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
