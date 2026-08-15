import 'package:flutter/services.dart';

/// Haptic feedback, named by *meaning* rather than by intensity.
///
/// The app previously called [HapticFeedback.selectionClick] in exactly one
/// place and nowhere else, which is why it felt like there was none at all:
/// `selectionClick` is the faintest constant Android offers, and it was only
/// fired after a control had already been committed. Everything else — the
/// steppers, the mode picker, the fan and flap controls, the power switch,
/// swiping between units — was silent.
///
/// Using semantic names keeps the *feel* consistent: a stepper tick should
/// never be as heavy as powering a unit on, no matter who wires it up later.
class Haptics {
  Haptics._();

  /// A discrete value moved one notch: temperature ±, a slider crossing a
  /// detent, swiping to another unit. The lightest thing that's still felt.
  static void tick() => HapticFeedback.selectionClick();

  /// A setting was chosen: mode, fan speed, a flap half, eco/turbo.
  static void select() => HapticFeedback.lightImpact();

  /// A consequential toggle — power on/off. Deliberately the most substantial
  /// feedback in the app, because it's the one action with a physical result
  /// you might be across the room from.
  static void toggle() => HapticFeedback.mediumImpact();

  /// Something finished well: pairing approved, a diagnosis with no failures.
  static void success() => HapticFeedback.mediumImpact();

  /// Something went wrong: a rejected key, a failed command, a failed check.
  /// Two beats so it's distinguishable from [toggle] without looking.
  static Future<void> failure() async {
    await HapticFeedback.heavyImpact();
    await Future.delayed(const Duration(milliseconds: 90));
    await HapticFeedback.heavyImpact();
  }
}
