// The forensic build: everything the app does, written down as it happens,
// and what it holds, on demand. Built only with
//
//   --dart-define=BREEZE_FORENSICS=true
//
// (the `ios-debug` branch's workflow does that); in any other build
// [kForensics] is false and every call here is compiled out.
//
// The log goes three ways: a ring in memory for the in-app viewer, a file per
// session in Documents/forensics (the Files app shows it, and so does the
// Apple Devices app on a PC), and the system log (debugPrint), where
// `idevicesyslog` on a computer reads it live. Credentials never reach any of
// them: see redact.dart.

import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import 'redact.dart';

const bool kForensics = bool.fromEnvironment('BREEZE_FORENSICS');

enum Level { debug, info, warn, error }

class Entry {
  Entry(this.at, this.ms, this.cat, this.level, this.text);
  final DateTime at;

  /// Milliseconds since the session started: the order and the gaps, even
  /// if the clock jumps.
  final int ms;
  final String cat;
  final Level level;
  final String text;

  String get line {
    final t = at.toIso8601String().substring(11, 23);
    final l = switch (level) { Level.debug => 'D', Level.info => 'I', Level.warn => 'W', Level.error => 'E' };
    return '$t +${(ms / 1000).toStringAsFixed(3)} $l [$cat] $text';
  }
}

/// How the previous session ended, read at start. iOS rarely tells an app it
/// is being ended, so this is a judgement: the last lifecycle state it wrote.
class PreviousSession {
  PreviousSession(this.file, this.lastState, this.lastLines, this.started, this.errors);
  final String file;
  final String lastState;
  final List<String> lastLines;
  final String started;
  final int errors;

  String get verdict => switch (lastState) {
        'resumed' => 'ended while on screen: a crash, or killed by the system (see crash reports)',
        'inactive' => 'ended while being left or covered (a call, Control Centre): likely a crash',
        'hidden' || 'paused' => 'ended in the background: most likely iOS reclaiming memory, which is normal',
        'detached' => 'ended cleanly',
        _ => 'unknown (no lifecycle state written)',
      };
}

class Forensics {
  Forensics._();
  static final Forensics I = Forensics._();

  static const _ringSize = 6000;
  static const _keepSessions = 20;

  final _ring = ListQueue<Entry>();
  final _clock = Stopwatch()..start();
  final DateTime started = DateTime.now();

  /// Bumped on every entry: what the viewer listens to.
  final ValueNotifier<int> changes = ValueNotifier(0);

  /// Errors (and warnings) since the viewer last looked: the badge.
  final ValueNotifier<int> unseenErrors = ValueNotifier(0);

  Directory? dir;
  File? sessionFile;
  File? _stateFile;
  RandomAccessFile? _out;
  PreviousSession? previous;
  int errorCount = 0;
  int warnCount = 0;
  String lifecycle = 'starting';

  List<Entry> get entries => List.unmodifiable(_ring);

  String get sessionName =>
      'session-${started.toIso8601String().substring(0, 19).replaceAll(':', '').replaceAll('-', '').replaceAll('T', '-')}';

  /// Open this session's file and read how the last one ended. Logging works
  /// before this (to memory and the system log); the file gets everything
  /// from here on, and the ring's earlier entries are written first.
  Future<void> start() async {
    try {
      final docs = await getApplicationDocumentsDirectory();
      final d = Directory('${docs.path}/forensics');
      await d.create(recursive: true);
      dir = d;
      previous = await _readPrevious(d);
      await _prune(d);
      sessionFile = File('${d.path}/$sessionName.log');
      _stateFile = File('${d.path}/$sessionName.state');
      _out = await sessionFile!.open(mode: FileMode.append);
      for (final e in _ring) {
        _write(e);
      }
      writeState();
    } catch (e, st) {
      log('forensics', 'cannot open the log file: $e', level: Level.error, stack: st);
    }
  }

  Future<PreviousSession?> _readPrevious(Directory d) async {
    final logs = d.listSync().whereType<File>().where((f) => f.path.endsWith('.log') && f.uri.pathSegments.last.startsWith('session-')).toList()
      ..sort((a, b) => a.path.compareTo(b.path));
    if (logs.isEmpty) return null;
    final last = logs.last;
    final stateFile = File(last.path.replaceAll(RegExp(r'\.log$'), '.state'));
    var state = '';
    if (stateFile.existsSync()) {
      try {
        state = (jsonDecode(stateFile.readAsStringSync()) as Map)['lifecycle'] as String? ?? '';
      } catch (_) {}
    }
    final lines = await last.readAsLines().catchError((_) => <String>[]);
    final errors = lines.where((l) => l.contains(' E [')).length;
    return PreviousSession(last.uri.pathSegments.last, state, lines.length > 60 ? lines.sublist(lines.length - 60) : lines,
        lines.isEmpty ? '' : lines.first, errors);
  }

  Future<void> _prune(Directory d) async {
    final sessions = d.listSync().whereType<File>().where((f) => f.uri.pathSegments.last.startsWith('session-')).toList()
      ..sort((a, b) => a.path.compareTo(b.path));
    final names = sessions.map((f) => f.uri.pathSegments.last.split('.').first).toSet().toList()..sort();
    for (final old in names.take((names.length - _keepSessions).clamp(0, names.length))) {
      for (final f in sessions.where((f) => f.uri.pathSegments.last.startsWith('$old.'))) {
        try {
          f.deleteSync();
        } catch (_) {}
      }
    }
  }

  /// Where this session stands, for the next one to read.
  void writeState() {
    try {
      _stateFile?.writeAsStringSync(jsonEncode({
        'lifecycle': lifecycle,
        'at': DateTime.now().toIso8601String(),
        'errors': errorCount,
        'warnings': warnCount,
      }), flush: true);
    } catch (_) {}
  }

  /// [text] is the app's own and written as it is; [error] came from
  /// elsewhere (an exception can quote a response) and is redacted.
  void log(String cat, String text, {Level level = Level.info, Object? error, StackTrace? stack}) {
    var t = text;
    if (error != null) t += ' | ${redactText('$error')}';
    if (stack != null) t += '\n$stack';
    final e = Entry(DateTime.now(), _clock.elapsedMilliseconds, cat, level, t);
    _ring.addLast(e);
    while (_ring.length > _ringSize) {
      _ring.removeFirst();
    }
    if (level == Level.error) errorCount++;
    if (level == Level.warn) warnCount++;
    if (level.index >= Level.warn.index) _unseen++;
    _write(e);
    // The system log cuts long lines: in pieces, each marked.
    final line = e.line;
    for (var i = 0; i < line.length; i += 900) {
      debugPrint('BREEZE ${line.substring(i, (i + 900).clamp(0, line.length))}');
    }
    _announce();
    if (level == Level.error) writeState();
  }

  int _unseen = 0;
  bool _announcing = false;

  /// The viewer and the button learn of new lines after the current frame,
  /// in one go: a line can be written during a build (a screen pushed, a
  /// widget's error), and a listener rebuilding then is an error of its own.
  void _announce() {
    if (_announcing) return;
    _announcing = true;
    scheduleMicrotask(() {
      _announcing = false;
      changes.value++;
      if (_unseen > 0) {
        unseenErrors.value += _unseen;
        _unseen = 0;
      }
    });
  }

  /// The viewer was looked at: no new warnings or errors since.
  void seen() {
    _unseen = 0;
    scheduleMicrotask(() => unseenErrors.value = 0);
  }

  void _write(Entry e) {
    final out = _out;
    if (out == null) return;
    try {
      // Flushed at once: what was written survives a crash a moment later.
      out.writeStringSync('${e.line}\n');
      out.flushSync();
    } catch (_) {}
  }

  /// A line of the user's own, to find a moment in the log later.
  void mark(String note) => log('mark', '======== $note ========', level: Level.warn);
}

/// Log, if this is the forensic build.
void flog(String cat, String text, {Level level = Level.info, Object? error, StackTrace? stack}) {
  if (kForensics) Forensics.I.log(cat, text, level: level, error: error, stack: stack);
}
