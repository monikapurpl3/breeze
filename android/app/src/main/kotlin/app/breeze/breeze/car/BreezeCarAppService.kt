package app.breeze.breeze.car

import android.content.Intent
import android.content.pm.ApplicationInfo
import androidx.car.app.CarAppService
import androidx.car.app.Screen
import androidx.car.app.Session
import androidx.car.app.validation.HostValidator

/**
 * Android Auto entry point. Registered under the `IOT` category — this is a
 * "control a thing in your house from the car" app, not navigation or media.
 *
 * Note for distribution: template apps outside navigation/media need Google
 * review to ship on Play. For a self-hosted APK, enable *Unknown sources* in
 * Android Auto's developer settings and it just works (see README).
 */
class BreezeCarAppService : CarAppService() {

    override fun createHostValidator(): HostValidator =
        if ((applicationInfo.flags and ApplicationInfo.FLAG_DEBUGGABLE) != 0) {
            // Debug builds also talk to the Desktop Head Unit, which isn't a
            // signed host. Release builds only trust Google's hosts.
            HostValidator.ALLOW_ALL_HOSTS_VALIDATOR
        } else {
            HostValidator.Builder(applicationContext)
                .addAllowedHosts(androidx.car.app.R.array.hosts_allowlist_sample)
                .build()
        }

    override fun onCreateSession(): Session = BreezeSession()
}

/** One connection to a head unit; hands back the only screen we have. */
class BreezeSession : Session() {
    override fun onCreateScreen(intent: Intent): Screen = PowerScreen(carContext)
}
