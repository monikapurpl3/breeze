package app.breeze.breeze

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.net.Uri
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetBackgroundIntent
import es.antonborri.home_widget.HomeWidgetLaunchIntent
import es.antonborri.home_widget.HomeWidgetProvider
import org.json.JSONObject
import java.util.Locale

/**
 * Home-screen widget for a single AC unit. Renders from data the Flutter app
 * stashes via `home_widget`; its buttons fire [HomeWidgetBackgroundIntent]s
 * that run the app's Dart `interactiveCallback` headlessly to control the unit.
 */
class BreezeUnitWidgetProvider : HomeWidgetProvider() {

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
        widgetData: SharedPreferences,
    ) {
        for (id in appWidgetIds) {
            val views = RemoteViews(context.packageName, R.layout.breeze_widget)
            val unitId = widgetData.getString("widget.$id", null)

            if (unitId == null) {
                renderUnconfigured(context, views, id)
            } else {
                val paired = widgetData.getString("paired", "1") != "0"
                val raw = widgetData.getString("state.$unitId", null)
                renderUnit(context, views, id, unitId, raw, paired)
            }
            appWidgetManager.updateAppWidget(id, views)
        }
    }

    /** No unit chosen yet — prompt, and make a tap re-open the config screen. */
    private fun renderUnconfigured(context: Context, views: RemoteViews, id: Int) {
        views.setTextViewText(R.id.widget_name, context.getString(R.string.widget_label))
        views.setTextViewText(R.id.widget_temp, context.getString(R.string.widget_dash))
        views.setTextViewText(R.id.widget_mode, context.getString(R.string.widget_not_configured))
        setControlsVisible(views, false)

        val configIntent = Intent(context, UnitConfigActivity::class.java).apply {
            putExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, id)
            // Distinct data so each widget's PendingIntent is unique.
            data = Uri.parse("breeze://configure/$id")
        }
        views.setOnClickPendingIntent(
            R.id.widget_root,
            PendingIntent.getActivity(context, id, configIntent, immutableFlags()),
        )
    }

    private fun renderUnit(
        context: Context,
        views: RemoteViews,
        id: Int,
        unitId: String,
        raw: String?,
        paired: Boolean,
    ) {
        var name = context.getString(R.string.widget_label)
        var power = false
        var online = true
        var target = Double.NaN
        var mode = ""

        if (raw != null) {
            try {
                val o = JSONObject(raw)
                name = o.optString("name", name)
                power = o.optBoolean("power", false)
                online = o.optBoolean("online", true)
                target = if (o.has("target")) o.optDouble("target") else Double.NaN
                mode = o.optString("mode", "")
            } catch (_: Exception) { /* keep defaults */ }
        }

        views.setTextViewText(R.id.widget_name, name)
        views.setTextViewText(
            R.id.widget_temp,
            if (target.isNaN()) context.getString(R.string.widget_dash)
            else String.format(Locale.US, "%.1f°", target),
        )
        setControlsVisible(views, true)

        // Not paired: tell the user to open the app, and route taps there.
        if (!paired) {
            views.setTextViewText(R.id.widget_mode, context.getString(R.string.widget_open_app))
            val launch = HomeWidgetLaunchIntent.getActivity(
                context, MainActivity::class.java, Uri.parse("homeWidget://open?unit=$unitId"),
            )
            for (btn in intArrayOf(
                R.id.widget_root, R.id.widget_btn_power,
                R.id.widget_btn_minus, R.id.widget_btn_plus, R.id.widget_btn_refresh,
            )) {
                views.setOnClickPendingIntent(btn, launch)
            }
            tintPower(context, views, on = false)
            return
        }

        val statusWord = if (!online) "offline" else if (power) "on" else "off"
        val modeLabel = modeLabels[mode] ?: mode.lowercase(Locale.US)
        views.setTextViewText(
            R.id.widget_mode,
            if (modeLabel.isEmpty()) statusWord else "$modeLabel · $statusWord",
        )
        tintPower(context, views, on = power && online)

        // Buttons → headless Dart control callback (see home_widget_service.dart).
        views.setOnClickPendingIntent(R.id.widget_btn_power, control(context, unitId, "power", id))
        views.setOnClickPendingIntent(R.id.widget_btn_minus, control(context, unitId, "tempDown", id))
        views.setOnClickPendingIntent(R.id.widget_btn_plus, control(context, unitId, "tempUp", id))
        views.setOnClickPendingIntent(R.id.widget_btn_refresh, control(context, unitId, "refresh", id))

        // Tapping the body opens the app.
        views.setOnClickPendingIntent(
            R.id.widget_root,
            HomeWidgetLaunchIntent.getActivity(
                context, MainActivity::class.java, Uri.parse("homeWidget://open?unit=$unitId"),
            ),
        )
    }

    private fun control(context: Context, unitId: String, action: String, widgetId: Int): PendingIntent {
        val uri = Uri.parse("homeWidget://control?action=$action&unit=$unitId&wid=$widgetId")
        return HomeWidgetBackgroundIntent.getBroadcast(context, uri)
    }

    private fun tintPower(context: Context, views: RemoteViews, on: Boolean) {
        val color = context.getColor(if (on) R.color.widget_accent else R.color.widget_icon)
        views.setInt(R.id.widget_btn_power, "setColorFilter", color)
    }

    private fun setControlsVisible(views: RemoteViews, visible: Boolean) {
        val v = if (visible) android.view.View.VISIBLE else android.view.View.GONE
        views.setViewVisibility(R.id.widget_btn_power, v)
        views.setViewVisibility(R.id.widget_btn_minus, v)
        views.setViewVisibility(R.id.widget_btn_plus, v)
        views.setViewVisibility(R.id.widget_btn_refresh, v)
    }

    private fun immutableFlags(): Int =
        PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE

    companion object {
        private val modeLabels = mapOf(
            "AUTO" to "auto", "COOL" to "cool", "DRY" to "dry",
            "HEAT" to "heat", "FAN_ONLY" to "fan",
        )

        /** Ask the framework to redraw the given widget instances. */
        fun updateIds(context: Context, ids: IntArray) {
            val intent = Intent(context, BreezeUnitWidgetProvider::class.java).apply {
                action = AppWidgetManager.ACTION_APPWIDGET_UPDATE
                putExtra(AppWidgetManager.EXTRA_APPWIDGET_IDS, ids)
            }
            context.sendBroadcast(intent)
        }
    }
}
