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

/// [accent] made dark (or light) enough to READ as text: at least 4.5:1, the
/// contrast text needs, against [on] -- the colour actually behind it, usually
/// a tint of the accent itself (see [layeredOnSurface]); the bare surface when
/// not given. The accents are chosen to tint surfaces, and as text on the
/// light theme they fell to 1.6:1 (dry) – 2.6:1 (auto). Only the lightness
/// moves, so a heat label is still warm and a cool one still cool.
Color readableAccent(Color accent, ColorScheme scheme, {Color? on}) {
  final bg = on ?? scheme.surface;
  double contrast(Color c) {
    final a = c.computeLuminance(), b = bg.computeLuminance();
    return (a > b ? a + 0.05 : b + 0.05) / (a > b ? b + 0.05 : a + 0.05);
  }

  // Towards black on a light background, towards white on a dark one. A
  // little over 4.5, so rounding in the drawn pixels cannot dip below it.
  final darken = bg.computeLuminance() > 0.5;
  var hsl = HSLColor.fromColor(accent);
  for (var i = 0; i < 50 && contrast(hsl.toColor()) < 4.7; i++) {
    final l = hsl.lightness + (darken ? -0.02 : 0.02);
    hsl = hsl.withLightness(l.clamp(0.0, 1.0));
  }
  return hsl.toColor();
}

/// What translucent fills stacked on [scheme]'s surface look like, bottom
/// layer first: the background to hand [readableAccent].
Color layeredOnSurface(ColorScheme scheme, List<Color> layers) =>
    layers.fold(scheme.surface, (under, over) => Color.alphaBlend(over, under));
