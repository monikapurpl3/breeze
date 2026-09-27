package app.breeze.breeze.car

import android.content.Intent
import android.util.Log
import androidx.car.app.CarAppService
import androidx.car.app.Screen
import androidx.car.app.Session
import androidx.car.app.validation.HostValidator

/**
 * Android Auto entry point. Registered under the `IOT` and `POI` categories
 * (see the manifest) — this is a "control a thing in your house from the car"
 * app, not navigation or media.
 *
 * Note for distribution: a real car lists this only if the app was installed
 * from Google Play (the internal testing track is enough, and is not
 * reviewed). Auto's *Unknown sources* setting does not apply to Car App
 * Library apps, and the refusal shows up only as
 * `CAR.VALIDATOR: Package DENIED; failed all other checks`. The Desktop Head
 * Unit lists a sideloaded build, unless its config gives it another car's
 * identity - which is how to check the real-car rule without a car.
 */
class BreezeCarAppService : CarAppService() {

    /**
     * Allow any host, including release builds.
     *
     * The stricter path used to be "release builds only trust Google's signed
     * hosts", via the library's sample allowlist. That's the right call for a
     * reviewed Play app, but this one is tested on the Desktop Head Unit, which
     * isn't a signed host, so the strict path made it untestable off a real
     * car, and any silent mismatch between that allowlist and the host on a
     * given phone fails invisibly - there is no log, the app simply never
     * works. What a rogue host could do here is toggle an air conditioner.
     * That trade is worth making; revisit it if this ever ships reviewed.
     */
    override fun createHostValidator(): HostValidator =
        HostValidator.ALLOW_ALL_HOSTS_VALIDATOR

    override fun onCreateSession(): Session {
        Log.i(TAG, "onCreateSession — host connected")
        return BreezeSession()
    }

    override fun onCreate() {
        super.onCreate()
        // Nothing here logged anything before, so a host that bound us and then
        // failed looked exactly like a host that never bound us at all.
        Log.i(TAG, "CarAppService created")
    }

    override fun onDestroy() {
        Log.i(TAG, "CarAppService destroyed")
        super.onDestroy()
    }

    companion object {
        const val TAG = "BreezeCar"
    }
}

/** One connection to a head unit; hands back the only screen we have. */
class BreezeSession : Session() {
    override fun onCreateScreen(intent: Intent): Screen {
        Log.i(BreezeCarAppService.TAG, "onCreateScreen — building PowerScreen")
        return PowerScreen(carContext)
    }
}
