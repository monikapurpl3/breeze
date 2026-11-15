// Translations: the app's own messages (lib/l10n/*.arb, generated into
// lib/l10n/gen) and Material's, from material_ui.
//
// The generated AppLocalizations.localizationsDelegates is not used: it lists
// the framework's own Material delegates, from flutter_localizations, and the
// app's widgets come from material_ui, which reads its own. Everything that
// builds a MaterialApp -- the app and every test -- uses [appLocalizationsDelegates].

import 'package:material_ui/material_ui.dart';

import '../l10n/gen/app_localizations.dart';

export '../l10n/gen/app_localizations.dart';

const List<LocalizationsDelegate<dynamic>> appLocalizationsDelegates = [
  AppLocalizations.delegate,
  ...GlobalMaterialLocalizations.delegates,
];

const List<Locale> appSupportedLocales = AppLocalizations.supportedLocales;

extension L10nContext on BuildContext {
  /// This screen's messages, in the app's current language.
  AppLocalizations get l10n => AppLocalizations.of(this);
}

/// A language the app speaks, as the picker lists it: by its own name, so a
/// person who cannot read the current language can still find theirs.
class AppLanguage {
  const AppLanguage(this.tag, this.name);

  /// The BCP 47 tag stored in the preferences and given to Android: `hr`, `sr`.
  final String tag;

  /// The language's name for itself.
  final String name;

  Locale get locale => Locale(tag);
}

/// In the picker's order: English first, as the template, then by name.
const List<AppLanguage> appLanguages = [
  AppLanguage('en', 'English'),
  AppLanguage('fr', 'Français'),
  AppLanguage('hr', 'Hrvatski'),
  AppLanguage('it', 'Italiano'),
  AppLanguage('sl', 'Slovenščina'),
  AppLanguage('sr', 'Српски'),
  AppLanguage('zh', '中文（简体）'),
];

/// Display only: the decimal separator of the app's current language -- a
/// comma in Croatian, Serbian, Slovenian, French and Italian -- set whenever
/// the app's language resolves. The wire is always a dot.
String decimalSeparator = '.';

void applyDecimalSeparator(Locale locale) {
  decimalSeparator =
      const {'hr', 'sr', 'sl', 'fr', 'it'}.contains(locale.languageCode) ? ',' : '.';
}

/// A number for display, with [digits] decimals and the language's separator.
String fmtDecimal(double value, int digits) =>
    value.toStringAsFixed(digits).replaceAll('.', decimalSeparator);

/// A mode's short name: `COOL` -> "cool", "hlađenje", "制冷".
String modeLabel(AppLocalizations l, String mode) => switch (mode) {
      'AUTO' => l.modeAuto,
      'COOL' => l.modeCool,
      'DRY' => l.modeDry,
      'HEAT' => l.modeHeat,
      'FAN_ONLY' => l.modeFan,
      _ => mode.toLowerCase(),
    };

/// A fan speed's name, by the wire value: the five steps of the fan control
/// (20 silent ... 100 max, the words `breeze-core control` uses) and 102 auto.
String fanSpeedLabel(AppLocalizations l, int speed) => switch (speed) {
      20 => l.fanSpeedSilent,
      40 => l.fanSpeedLow,
      60 => l.fanSpeedMedium,
      80 => l.fanSpeedHigh,
      100 => l.fanSpeedMax,
      102 => l.fanSpeedAuto,
      _ => '$speed',
    };

/// A swing setting's name: `VERTICAL` -> "vertical".
String swingLabel(AppLocalizations l, String swing) => switch (swing) {
      'OFF' => l.swingOff,
      'VERTICAL' => l.swingVertical,
      'HORIZONTAL' => l.swingHorizontal,
      'BOTH' => l.swingBoth,
      _ => swing.toLowerCase(),
    };
