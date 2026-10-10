// The Nerd screen's Internal tab: settings nobody needs, kept out of the way.
//
// They change how the app looks and connects rather than what it does, so
// they live in SharedPreferences beside the display preferences, not in the
// secure store. (The per-server ones -- fallback addresses, a pinned auth
// version -- are part of a server profile and live with it, in SecureStore.)

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Where the app's colours come from.
enum ColourSource {
  /// Material You: the wallpaper's palette where the system offers one
  /// (Android 12+), the built-in teal otherwise.
  wallpaper,

  /// A colour of the user's choosing, on every platform. What iOS users get
  /// instead of a wallpaper palette, which iOS doesn't offer.
  custom,
}

class InternalPrefs {
  ColourSource colourSource = ColourSource.wallpaper;
  int seedColour = defaultSeed;
  DynamicSchemeVariant schemeVariant = DynamicSchemeVariant.tonalSpot;
  bool showUnitIp = false;
  bool showLatency = false;
  int timeoutSeconds = defaultTimeoutSeconds;
  bool liveUpdates = true;
  bool haptics = true;

  /// The user's own cat facts, shown while the app waits on the server.
  List<String> catFacts = const [];
  bool builtInCatFacts = true;

  static const int defaultSeed = 0xFF4FD1C5; // teal, matches the web panel
  static const int defaultTimeoutSeconds = 15;
  static const int minTimeoutSeconds = 3;
  static const int maxTimeoutSeconds = 60;

  static const _k = 'internal_';

  static Future<InternalPrefs> load() async {
    final p = await SharedPreferences.getInstance();
    final i = InternalPrefs();
    i.colourSource = p.getString('${_k}colour_source') == 'custom'
        ? ColourSource.custom
        : ColourSource.wallpaper;
    i.seedColour = p.getInt('${_k}seed') ?? defaultSeed;
    final variant = p.getString('${_k}variant');
    i.schemeVariant = DynamicSchemeVariant.values.firstWhere(
      (v) => v.name == variant,
      orElse: () => DynamicSchemeVariant.tonalSpot,
    );
    i.showUnitIp = p.getBool('${_k}show_ip') ?? false;
    i.showLatency = p.getBool('${_k}show_latency') ?? false;
    i.timeoutSeconds = (p.getInt('${_k}timeout') ?? defaultTimeoutSeconds)
        .clamp(minTimeoutSeconds, maxTimeoutSeconds);
    i.liveUpdates = p.getBool('${_k}live') ?? true;
    i.haptics = p.getBool('${_k}haptics') ?? true;
    i.catFacts = p.getStringList('${_k}cat_facts') ?? const [];
    i.builtInCatFacts = p.getBool('${_k}cat_builtin') ?? true;
    return i;
  }

  Future<void> save() async {
    final p = await SharedPreferences.getInstance();
    await p.setString('${_k}colour_source', colourSource.name);
    await p.setInt('${_k}seed', seedColour);
    await p.setString('${_k}variant', schemeVariant.name);
    await p.setBool('${_k}show_ip', showUnitIp);
    await p.setBool('${_k}show_latency', showLatency);
    await p.setInt('${_k}timeout', timeoutSeconds);
    await p.setBool('${_k}live', liveUpdates);
    await p.setBool('${_k}haptics', haptics);
    await p.setStringList('${_k}cat_facts', catFacts);
    await p.setBool('${_k}cat_builtin', builtInCatFacts);
  }

  /// Everything back to how the app ships.
  static Future<InternalPrefs> reset() async {
    final p = await SharedPreferences.getInstance();
    for (final key in p.getKeys().where((k) => k.startsWith(_k)).toList()) {
      await p.remove(key);
    }
    return InternalPrefs();
  }
}
