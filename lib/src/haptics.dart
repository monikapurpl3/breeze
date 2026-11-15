import 'package:flutter/foundation.dart';
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
///
/// **On Android these drive the vibrator itself** (MainActivity.kt), not
/// [HapticFeedback]. That goes through Android's touch-feedback path, and
/// with the phone's "Touch interactions" vibration switched off -- which
/// many people have -- it vibrates nothing while reporting success. Proven on
/// a Galaxy with a debug build in November 2026: the touch-feedback path
/// silent, the vibrator felt every time. iOS keeps [HapticFeedback].
class Haptics {
  Haptics._();

  /// Off from the Nerd screen's Internal tab. Every call below goes quiet;
  /// nothing that calls them needs to know.
  static bool enabled = true;

  static const MethodChannel _vibrator = MethodChannel('app.breeze/haptics');

  /// The vibrator on Android; [elsewhere] (Flutter's haptics) everywhere
  /// else, and on Android too if the channel is somehow missing.
  static Future<void> _buzz(String kind, Future<void> Function() elsewhere) async {
    if (!enabled) return;
    if (defaultTargetPlatform == TargetPlatform.android) {
      try {
        await _vibrator.invokeMethod<void>('vibrate', kind);
        return;
      } catch (_) {
        // MissingPluginException in tests, or a platform that lacks it.
      }
    }
    await elsewhere();
  }

  /// A discrete value moved one notch: temperature ±, a slider crossing a
  /// detent, swiping to another unit. The lightest thing that's still felt.
  static void tick() => _buzz('tick', HapticFeedback.selectionClick);

  /// A setting was chosen: mode, fan speed, a flap half, eco/turbo.
  static void select() => _buzz('select', HapticFeedback.lightImpact);

  /// A consequential toggle — power on/off. Deliberately the most substantial
  /// feedback in the app, because it's the one action with a physical result
  /// you might be across the room from.
  static void toggle() => _buzz('toggle', HapticFeedback.mediumImpact);

  /// Something finished well: pairing approved, a diagnosis with no failures.
  static void success() => _buzz('success', HapticFeedback.mediumImpact);

  /// Something went wrong: a rejected key, a failed command, a failed check.
  /// Two beats so it's distinguishable from [toggle] without looking.
  static Future<void> failure() => _buzz('failure', () async {
        await HapticFeedback.heavyImpact();
        await Future.delayed(const Duration(milliseconds: 90));
        await HapticFeedback.heavyImpact();
      });
}
