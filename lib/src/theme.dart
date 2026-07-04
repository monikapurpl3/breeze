// Theme helpers. Colours come from the Material You scheme (dynamic on
// Android 12+, seeded fallback otherwise) — there are no fixed brand
// colours. COOL and the default use the scheme's primary directly; the
// warmer modes keep a semantic hue but are *harmonized* into the active
// palette so they blend with the wallpaper-derived colours instead of
// clashing.

import 'package:dynamic_color/dynamic_color.dart';
import 'package:flutter/material.dart';

/// Accent colour for an operational mode, expressed through the scheme.
Color accentForMode(String mode, ColorScheme scheme) {
  final Color? semantic = switch (mode) {
    'HEAT' => const Color(0xFFF0954B),
    'DRY' => const Color(0xFFE0B93A),
    'FAN_ONLY' => const Color(0xFF7F9CB5),
    'AUTO' => const Color(0xFF9D7CD8),
    _ => null, // COOL / default → pure Material You primary
  };
  return semantic == null ? scheme.primary : semantic.harmonizeWith(scheme.primary);
}

const List<String> kWeekdayShort = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
