package app.breeze.breeze

import android.content.Context
import android.os.Build
import android.os.VibrationEffect
import android.os.Vibrator
import android.os.VibratorManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "app.breeze/haptics")
            .setMethodCallHandler { call, result ->
                if (call.method == "vibrate") {
                    vibrate(call.arguments as? String ?: "")
                    result.success(null)
                } else {
                    result.notImplemented()
                }
            }
    }

    private fun vibrator(): Vibrator? =
        if (Build.VERSION.SDK_INT >= 31) {
            (getSystemService(Context.VIBRATOR_MANAGER_SERVICE) as? VibratorManager)?.defaultVibrator
        } else {
            @Suppress("DEPRECATION")
            getSystemService(Context.VIBRATOR_SERVICE) as? Vibrator
        }

    /**
     * The app's haptics, from the vibrator itself.
     *
     * Not View.performHapticFeedback, which Flutter's HapticFeedback uses:
     * that is Android's touch-feedback path, and with the phone's "Touch
     * interactions" vibration switched off it vibrates nothing while still
     * reporting success, so on such phones the app had no haptics at all. The
     * vibrator still honours the phone's vibration intensity and silent mode,
     * and the app's own switch (Nerd screen, Internal) decides whether this is
     * called at all.
     */
    private fun vibrate(kind: String) {
        val vib = vibrator() ?: return
        if (!vib.hasVibrator()) return
        when {
            Build.VERSION.SDK_INT >= 29 -> {
                val effect = when (kind) {
                    "tick" -> VibrationEffect.EFFECT_TICK
                    "select" -> VibrationEffect.EFFECT_CLICK
                    "toggle", "success" -> VibrationEffect.EFFECT_HEAVY_CLICK
                    "failure" -> VibrationEffect.EFFECT_DOUBLE_CLICK
                    else -> return
                }
                vib.vibrate(VibrationEffect.createPredefined(effect))
            }
            Build.VERSION.SDK_INT >= 26 -> {
                val effect = when (kind) {
                    "tick" -> VibrationEffect.createOneShot(8, 70)
                    "select" -> VibrationEffect.createOneShot(12, 140)
                    "toggle", "success" -> VibrationEffect.createOneShot(25, 255)
                    "failure" -> VibrationEffect.createWaveform(
                        longArrayOf(0, 30, 90, 30), intArrayOf(0, 255, 0, 255), -1,
                    )
                    else -> return
                }
                vib.vibrate(effect)
            }
            else -> {
                @Suppress("DEPRECATION")
                vib.vibrate(
                    when (kind) {
                        "tick" -> 10L
                        "select" -> 15L
                        "failure" -> 60L
                        else -> 30L
                    },
                )
            }
        }
    }
}
