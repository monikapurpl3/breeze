// The keychain as SecureStore uses it, with every call written down: which
// key, whether a value came back and how long it was, how long the call took,
// and the full error if it failed. Values never: see redact.dart. On iOS a
// failing keychain (locked before the first unlock, or items written by
// another signing team) is a classic cause of "logged out for no reason".

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'forensics.dart';
import 'redact.dart';

class LoggedSecureStorage {
  LoggedSecureStorage(this._s);
  final FlutterSecureStorage _s;

  Future<T> _timed<T>(String what, Future<T> Function() call, String Function(T) describe) async {
    final clock = Stopwatch()..start();
    try {
      final v = await call();
      flog('keychain', '$what -> ${describe(v)} (${clock.elapsedMilliseconds} ms)', level: Level.debug);
      return v;
    } catch (e, st) {
      flog('keychain', '$what FAILED after ${clock.elapsedMilliseconds} ms', level: Level.error, error: e, stack: st);
      rethrow;
    }
  }

  Future<String?> read({required String key}) =>
      _timed('read $key', () => _s.read(key: key), (v) => v == null ? 'absent' : 'present, ${v.length} chars');

  Future<void> write({required String key, required String? value}) => _timed(
      'write $key (${value == null ? 'null' : '${value.length} chars'})', () => _s.write(key: key, value: value), (_) => 'ok');

  Future<void> delete({required String key}) => _timed('delete $key', () => _s.delete(key: key), (_) => 'ok');

  /// Every item, for the snapshot: reported there as key, length and
  /// fingerprint only.
  Future<Map<String, String>> readAll() => _timed('readAll', () => _s.readAll(), (m) => '${m.length} items');

  /// The inventory as the snapshot shows it: never a value.
  Future<List<String>> inventory() async {
    final all = await readAll();
    final keys = all.keys.toList()..sort();
    return [for (final k in keys) '$k: ${fingerprint(all[k]!)}'];
  }
}
