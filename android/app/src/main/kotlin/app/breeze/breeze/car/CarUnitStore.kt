package app.breeze.breeze.car

import android.content.Context
import android.content.SharedPreferences
import android.net.Uri
import es.antonborri.home_widget.HomeWidgetBackgroundIntent
import org.json.JSONArray
import org.json.JSONObject

/** One unit as listed by the phone app. */
data class CarUnit(val id: String, val name: String)

/** Last-known state of a unit, as cached for the widgets. */
data class CarUnitState(
    val name: String?,
    val online: Boolean,
    val power: Boolean,
    val target: Double?,
    val mode: String?,
)

/**
 * The car app's data layer — and deliberately **not** a second API client.
 *
 * The Flutter app already caches the unit list and each unit's state into the
 * shared `HomeWidgetPreferences` (see home_widget_service.dart), and already
 * routes widget button taps through a headless Dart isolate that authenticates
 * exactly like the foreground app (Ed25519 request signing, credentials in the
 * Keystore). This reads that same cache and fires that same broadcast, so the
 * car surface gets authenticated control **without** re-implementing the
 * signing scheme in Kotlin or touching the private key.
 *
 * Consequence worth knowing: control is fire-and-forget. The Dart isolate
 * performs the call and writes the fresh state back to these preferences, which
 * is why [registerListener] exists — the screen redraws when the real state
 * lands.
 */
class CarUnitStore(private val context: Context) {

    private val prefs: SharedPreferences =
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)

    /** False once the phone app finds it has no usable credentials. */
    fun isPaired(): Boolean = prefs.getString(KEY_PAIRED, "1") != "0"

    /** Units in the same order the phone app shows them. */
    fun units(): List<CarUnit> {
        val raw = prefs.getString(KEY_UNIT_LIST, null) ?: return emptyList()
        return try {
            val arr = JSONArray(raw)
            (0 until arr.length()).mapNotNull { i ->
                val o = arr.optJSONObject(i) ?: return@mapNotNull null
                val id = o.optString("id").takeIf { it.isNotEmpty() } ?: return@mapNotNull null
                CarUnit(id, o.optString("name", id))
            }
        } catch (_: Exception) {
            emptyList()
        }
    }

    /** Last-known state, or null if the phone app hasn't cached one yet. */
    fun state(unitId: String): CarUnitState? {
        val raw = prefs.getString("$KEY_STATE_PREFIX$unitId", null) ?: return null
        return try {
            val o = JSONObject(raw)
            CarUnitState(
                name = o.optString("name").takeIf { it.isNotEmpty() },
                online = o.optBoolean("online", true),
                power = o.optBoolean("power", false),
                target = if (o.has("target")) o.optDouble("target") else null,
                mode = o.optString("mode").takeIf { it.isNotEmpty() },
            )
        } catch (_: Exception) {
            null
        }
    }

    /**
     * Toggle power via the headless Dart callback (the same URI shape the home
     * screen widget's power button uses; `wid` is omitted because the callback
     * only reads `action` and `unit`).
     */
    fun togglePower(unitId: String): Boolean = try {
        HomeWidgetBackgroundIntent
            .getBroadcast(context, Uri.parse("homeWidget://control?action=power&unit=$unitId"))
            .send()
        true
    } catch (_: Exception) {
        false // a dead PendingIntent must not take the car UI down
    }

    fun registerListener(l: SharedPreferences.OnSharedPreferenceChangeListener) =
        prefs.registerOnSharedPreferenceChangeListener(l)

    fun unregisterListener(l: SharedPreferences.OnSharedPreferenceChangeListener) =
        prefs.unregisterOnSharedPreferenceChangeListener(l)

    private companion object {
        // Must match home_widget's store + the keys in home_widget_service.dart.
        const val PREFS = "HomeWidgetPreferences"
        const val KEY_UNIT_LIST = "unit_list"
        const val KEY_PAIRED = "paired"
        const val KEY_STATE_PREFIX = "state."
    }
}
