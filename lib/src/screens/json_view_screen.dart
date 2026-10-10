// A read-only look at what the server holds, as JSON: the programs
// (favourites, schedules, curves) or the pending timers. Reached from the
// Nerd screen's Internal tab. Nothing here can change anything -- it is for
// seeing exactly what the server has, and copying it into a bug report.

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../api_client.dart';
import '../haptics.dart';

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
            ? 'This server does not have that yet.'
            : e.message);
      }
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
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
      const SnackBar(content: Text('Copied to the clipboard')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        actions: [
          IconButton(
            tooltip: 'Copy the JSON',
            icon: const Icon(Icons.copy_all_outlined),
            onPressed: _items == null ? null : _copy,
          ),
          IconButton(
            tooltip: 'Refresh',
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
                    label: Text('All (${_items!.length})'),
                    selected: _kind == null,
                    onSelected: (_) => setState(() => _kind = null),
                  ),
                  for (final k in widget.kinds)
                    ChoiceChip(
                      label: Text(
                          '${k[0].toUpperCase()}${k.substring(1)}s '
                          '(${_items!.where((e) => e is Map && e['kind'] == k).length})'),
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
        child: Text('Nothing here: []',
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
