// The native half of the forensic build (ios/Runner/AppDelegate.swift): what
// only iOS can say -- the device, the keychain's own view of the app's items,
// the provisioning profile it was signed with, the network path -- and the
// events it sees (memory warnings, thermal state, the keychain locking).
// Anywhere else (Android, tests) every call answers "not available".

import 'package:flutter/services.dart';

import 'forensics.dart';

const _channel = MethodChannel('breeze/forensics');

bool _listening = false;

/// Native events into the log, from now on and since launch.
Future<void> listenToNative() async {
  if (_listening) return;
  _listening = true;
  _channel.setMethodCallHandler((call) async {
    if (call.method == 'event') flog('ios', '${call.arguments}');
    return null;
  });
  try {
    final early = await _channel.invokeListMethod<String>('drain') ?? const [];
    for (final e in early) {
      flog('ios', '(before Dart) $e');
    }
  } on MissingPluginException {
    flog('ios', 'no native forensics on this platform', level: Level.debug);
  } catch (e) {
    flog('ios', 'native forensics did not answer', level: Level.warn, error: e);
  }
}

Future<Map<String, Object?>> _map(String method) async {
  try {
    final m = await _channel.invokeMapMethod<String, Object?>(method);
    return m ?? const {};
  } on MissingPluginException {
    return const {'available': 'no (not iOS, or not the forensic build)'};
  } catch (e) {
    return {'error': '$e'};
  }
}

/// A TCP connection through iOS's own networking (not dart:io): it says
/// outright when the local network permission is what stops it. Null where
/// there is no native side.
Future<Map<String, Object?>?> nativeConnect(String host, int port) async {
  try {
    return await _channel.invokeMapMethod<String, Object?>('connect', {'host': host, 'port': port});
  } on MissingPluginException {
    return null;
  } catch (e) {
    return {'state': 'error', 'error': '$e'};
  }
}

Future<Map<String, Object?>> nativeInfo() => _map('info');
Future<Map<String, Object?>> keychainItems() => _map('keychain');
Future<Map<String, Object?>> provisioning() => _map('provisioning');

/// iOS's keychain accessibility codes, as Apple names them.
String accessibilityName(String code) => switch (code) {
      'ak' => 'when unlocked',
      'aku' => 'when unlocked, this device only',
      'ck' => 'after first unlock',
      'cku' => 'after first unlock, this device only',
      'akpu' => 'when passcode set, this device only',
      'dk' => 'always (deprecated)',
      'dku' => 'always, this device only (deprecated)',
      _ => code,
    };
