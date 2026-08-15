import 'dart:math';

/// Suggests a default name for **this device** at pairing time.
///
/// Every install used to propose "Breeze", so a household ended up with several
/// identically-named entries in the server's device list and no way to tell
/// which phone to revoke. (Labels aren't identity — the server keys on a
/// token id — so duplicates were harmless, just useless to a human.)
///
/// The shape is a climate word plus seven digits: `Mistral-4820937`. Long
/// enough that a collision is unlikely, short enough to read aloud, and it
/// never encodes anything about the device.
class DeviceName {
  DeviceName._();

  /// Words that read as "air conditioning" without being twee.
  static const _words = <String>[
    'Breeze',
    'Mistral',
    'Zephyr',
    'Chinook',
    'Sirocco',
    'Monsoon',
    'Draft',
    'Gust',
    'Squall',
    'Flurry',
    'Frost',
    'Glacier',
    'Tundra',
    'Blizzard',
    'Icicle',
    'Permafrost',
    'Chill',
    'Cooler',
    'Radiator',
    'Condenser',
    'Compressor',
    'Evaporator',
    'Thermostat',
    'Refrigerant',
    'Vent',
    'Duct',
    'Damper',
    'Louvre',
    'Plenum',
    'Airflow',
    'Downdraft',
    'Updraft',
    'Crosswind',
    'Trade Wind',
    'Aurora',
    'Alpine',
    'Arctic',
    'Boreal',
    'Nimbus',
    'Cirrus',
  ];

  static final _rnd = Random();

  /// e.g. `Sirocco-4820937`. Uses [Random] rather than [Random.secure] on
  /// purpose: this is a human label, not a credential — the actual identity is
  /// the Ed25519 key generated at enrolment.
  static String suggest() {
    final word = _words[_rnd.nextInt(_words.length)];
    final digits = List.generate(7, (_) => _rnd.nextInt(10)).join();
    return '$word-$digits';
  }
}
