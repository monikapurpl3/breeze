package app.breeze.breeze

import android.app.Activity
import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.Intent
import android.os.Bundle
import android.view.View
import android.widget.ArrayAdapter
import android.widget.ListView
import android.widget.TextView
import org.json.JSONArray

/**
 * Widget placement configuration: lets the user pick which unit this widget
 * instance controls. Reads the unit list the Flutter app cached into the
 * shared `HomeWidgetPreferences`, writes `widget.<appWidgetId>` = unitId, and
 * asks the provider to render.
 */
class UnitConfigActivity : Activity() {

    private var appWidgetId = AppWidgetManager.INVALID_APPWIDGET_ID

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // Default to CANCELED so dismissing the dialog doesn't place the widget.
        setResult(RESULT_CANCELED)
        setContentView(R.layout.breeze_widget_config)

        appWidgetId = intent?.extras?.getInt(
            AppWidgetManager.EXTRA_APPWIDGET_ID,
            AppWidgetManager.INVALID_APPWIDGET_ID,
        ) ?: AppWidgetManager.INVALID_APPWIDGET_ID
        if (appWidgetId == AppWidgetManager.INVALID_APPWIDGET_ID) {
            finish()
            return
        }

        val prefs = getSharedPreferences("HomeWidgetPreferences", Context.MODE_PRIVATE)
        val ids = ArrayList<String>()
        val names = ArrayList<String>()
        prefs.getString("unit_list", null)?.let { raw ->
            try {
                val arr = JSONArray(raw)
                for (i in 0 until arr.length()) {
                    val o = arr.getJSONObject(i)
                    val uid = o.getString("id")
                    ids.add(uid)
                    names.add(o.optString("name", uid))
                }
            } catch (_: Exception) { /* show the empty hint below */ }
        }

        val empty = findViewById<TextView>(R.id.config_empty)
        val list = findViewById<ListView>(R.id.config_list)

        if (names.isEmpty()) {
            empty.visibility = View.VISIBLE
            list.visibility = View.GONE
            return
        }

        list.adapter = ArrayAdapter(this, android.R.layout.simple_list_item_1, names)
        list.setOnItemClickListener { _, _, pos, _ ->
            prefs.edit().putString("widget.$appWidgetId", ids[pos]).apply()
            BreezeUnitWidgetProvider.updateIds(this, intArrayOf(appWidgetId))
            setResult(
                RESULT_OK,
                Intent().putExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, appWidgetId),
            )
            finish()
        }
    }
}
