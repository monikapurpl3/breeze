package app.breeze.breeze.car

import android.content.SharedPreferences
import android.os.Handler
import android.os.Looper
import androidx.car.app.CarContext
import androidx.car.app.Screen
import androidx.car.app.model.Action
import androidx.car.app.model.ActionStrip
import androidx.car.app.model.CarColor
import androidx.car.app.model.CarIcon
import androidx.car.app.model.GridItem
import androidx.car.app.model.ItemList
import androidx.car.app.model.GridTemplate
import androidx.car.app.model.MessageTemplate
import androidx.car.app.model.Template
import androidx.core.graphics.drawable.IconCompat
import androidx.lifecycle.DefaultLifecycleObserver
import androidx.lifecycle.LifecycleOwner
import app.breeze.breeze.R

/**
 * The whole car app: **one unit per screen, and nothing on it but a huge power
 * button**, with the unit's name in the header above it. Big previous/next
 * actions step between units.
 *
 * Deliberately this bare: the driver should be able to hit it without reading.
 * Temperature, mode, fan and everything else stay on the phone.
 *
 * Everything is drawn with the Car App Library's templates, which the *host*
 * (Android Auto) renders and sizes — an app can't paint its own pixels here, by
 * design, so "huge" means the largest primitive available: a single-item grid,
 * which hosts render as one big centred, tappable tile.
 */
class PowerScreen(carContext: CarContext) : Screen(carContext) {

    private val store = CarUnitStore(carContext)
    private var index = 0

    /**
     * Shown instead of the cached value right after a tap. Control goes through
     * a headless isolate and a LAN round-trip, so without this the button would
     * sit unchanged for a second or so and invite a second press.
     */
    private var optimisticPower: Boolean? = null

    private val handler = Handler(Looper.getMainLooper())

    /** Safety net: if no fresh state arrives (unit offline, control failed), stop lying. */
    private val dropOptimistic = Runnable {
        optimisticPower = null
        invalidate()
    }

    private val prefsListener = SharedPreferences.OnSharedPreferenceChangeListener { _, _ ->
        // Real state landed — drop the optimistic value and redraw from cache.
        handler.post {
            optimisticPower = null
            handler.removeCallbacks(dropOptimistic)
            invalidate()
        }
    }

    init {
        lifecycle.addObserver(object : DefaultLifecycleObserver {
            override fun onStart(owner: LifecycleOwner) = store.registerListener(prefsListener)
            override fun onStop(owner: LifecycleOwner) {
                store.unregisterListener(prefsListener)
                handler.removeCallbacks(dropOptimistic)
            }
        })
    }

    override fun onGetTemplate(): Template {
        val units = store.units()

        if (!store.isPaired()) return message(R.string.car_not_paired)
        if (units.isEmpty()) return message(R.string.car_no_units)

        // The phone app can add or remove units while we're parked on one.
        if (index >= units.size) index = 0
        val unit = units[index]
        val snapshot = store.state(unit.id)
        val on = optimisticPower ?: (snapshot?.power ?: false)
        val online = snapshot?.online ?: false

        val powerItem = GridItem.Builder()
            .setImage(
                CarIcon.Builder(
                    IconCompat.createWithResource(carContext, R.drawable.ic_car_power),
                )
                    // Colour is the state cue: green running, red stopped.
                    .setTint(if (on) CarColor.GREEN else CarColor.RED)
                    .build(),
                GridItem.IMAGE_TYPE_ICON,
            )
            .setTitle(
                carContext.getString(if (on) R.string.car_state_on else R.string.car_state_off),
            )
            .setText(
                carContext.getString(
                    when {
                        !online -> R.string.car_offline
                        on -> R.string.car_tap_to_turn_off
                        else -> R.string.car_tap_to_turn_on
                    },
                ),
            )
            .setOnClickListener { onPowerTap(unit.id, on) }
            .build()

        val builder = GridTemplate.Builder()
            // The unit's name, above the button.
            .setTitle(snapshot?.name ?: unit.name)
            .setHeaderAction(Action.APP_ICON)
            .setSingleList(ItemList.Builder().addItem(powerItem).build())

        // Only offer stepping when there's somewhere to step to.
        if (units.size > 1) builder.setActionStrip(unitSwitcher())

        return builder.build()
    }

    private fun unitSwitcher(): ActionStrip = ActionStrip.Builder()
        .addAction(
            Action.Builder()
                .setIcon(icon(R.drawable.ic_car_prev))
                .setOnClickListener { step(-1) }
                .build(),
        )
        .addAction(
            Action.Builder()
                .setIcon(icon(R.drawable.ic_car_next))
                .setOnClickListener { step(1) }
                .build(),
        )
        .build()

    private fun icon(res: Int): CarIcon =
        CarIcon.Builder(IconCompat.createWithResource(carContext, res)).build()

    private fun message(res: Int): Template = MessageTemplate.Builder(carContext.getString(res))
        .setTitle(carContext.getString(R.string.car_title))
        .setHeaderAction(Action.APP_ICON)
        .build()

    /** Wrap around, so the driver can keep pressing one button to cycle. */
    private fun step(delta: Int) {
        val size = store.units().size
        if (size == 0) return
        index = ((index + delta) % size + size) % size
        optimisticPower = null
        handler.removeCallbacks(dropOptimistic)
        invalidate()
    }

    private fun onPowerTap(unitId: String, currentlyOn: Boolean) {
        if (!store.togglePower(unitId)) return
        optimisticPower = !currentlyOn
        handler.removeCallbacks(dropOptimistic)
        handler.postDelayed(dropOptimistic, OPTIMISTIC_TIMEOUT_MS)
        invalidate()
    }

    private companion object {
        const val OPTIMISTIC_TIMEOUT_MS = 6_000L
    }
}
