package com.pitanie.pitanie_widgets

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.view.View
import android.widget.RemoteViews
import org.json.JSONObject
import java.util.Calendar
import kotlin.math.max
import kotlin.math.roundToInt

/** Локальное хранилище снимка дня для виджетов. */
object WidgetStore {
    private const val PREFS = "pitanie_widget_prefs"
    private const val KEY = "snapshot"

    fun save(context: Context, json: String) {
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit().putString(KEY, json).apply()
    }

    fun read(context: Context): JSONObject? {
        val s = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).getString(KEY, null)
            ?: return null
        return try {
            JSONObject(s)
        } catch (e: Exception) {
            null
        }
    }
}

object WidgetRenderer {
    private fun todayKey(): String {
        val c = Calendar.getInstance()
        return String.format(
            "%04d-%02d-%02d", c.get(Calendar.YEAR), c.get(Calendar.MONTH) + 1,
            c.get(Calendar.DAY_OF_MONTH)
        )
    }

    private fun open(context: Context, action: String, code: Int): PendingIntent {
        val intent = context.packageManager.getLaunchIntentForPackage(context.packageName)
            ?: Intent()
        intent.data = Uri.parse("pitanie://widget/$action")
        intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP)
        return PendingIntent.getActivity(
            context, code, intent, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
    }

    private fun n(v: Double): String = max(0.0, v).roundToInt().toString()

    /** Строит содержимое виджета. [medium]: крупный виджет с БЖУ, водой и кнопками. */
    fun build(context: Context, medium: Boolean): RemoteViews {
        val views = RemoteViews(
            context.packageName,
            if (medium) R.layout.pitanie_widget_medium else R.layout.pitanie_widget_small
        )
        val snap = WidgetStore.read(context)
        val enabled = snap?.optBoolean("enabled", false) ?: false
        val fresh = snap != null && snap.optString("day") == todayKey()

        views.setOnClickPendingIntent(
            R.id.pw_root, open(context, if (enabled) "nutrition" else "settings", 10)
        )

        if (!enabled || !fresh) {
            views.setViewVisibility(R.id.pw_content, View.GONE)
            views.setViewVisibility(R.id.pw_message, View.VISIBLE)
            views.setTextViewText(
                R.id.pw_message,
                context.getString(
                    if (!enabled) R.string.pw_disabled else R.string.pw_open_app
                )
            )
            if (medium) setButtons(context, views)
            return views
        }

        views.setViewVisibility(R.id.pw_content, View.VISIBLE)
        views.setViewVisibility(R.id.pw_message, View.GONE)

        val eaten = snap!!.optDouble("kcal", 0.0)
        val goal = snap.optDouble("kcalGoal", 0.0)
        val left = goal - eaten
        views.setTextViewText(
            R.id.pw_main,
            if (left >= 0) n(left) else "+" + n(-left)
        )
        views.setTextViewText(
            R.id.pw_main_label,
            context.getString(if (left >= 0) R.string.pw_left else R.string.pw_over)
        )
        views.setTextViewText(
            R.id.pw_sub, context.getString(R.string.pw_eaten_of, n(eaten), n(goal))
        )
        views.setProgressBar(R.id.pw_kcal_bar, 1000, progress(eaten, goal), false)

        val water = snap.optDouble("water", 0.0)
        val waterGoal = snap.optDouble("waterGoal", 0.0)
        views.setTextViewText(
            R.id.pw_water,
            context.getString(
                if (medium) R.string.pw_water_of else R.string.pw_water_short, n(water), n(waterGoal)
            )
        )
        views.setProgressBar(R.id.pw_water_bar, 1000, progress(water, waterGoal), false)

        if (medium) {
            val p = snap.optDouble("p"); val pg = snap.optDouble("pGoal")
            val f = snap.optDouble("f"); val fg = snap.optDouble("fGoal")
            val c = snap.optDouble("c"); val cg = snap.optDouble("cGoal")
            views.setTextViewText(R.id.pw_p, context.getString(R.string.pw_protein, n(p), n(pg)))
            views.setTextViewText(R.id.pw_f, context.getString(R.string.pw_fat, n(f), n(fg)))
            views.setTextViewText(R.id.pw_c, context.getString(R.string.pw_carbs, n(c), n(cg)))
            views.setProgressBar(R.id.pw_p_bar, 1000, progress(p, pg), false)
            views.setProgressBar(R.id.pw_f_bar, 1000, progress(f, fg), false)
            views.setProgressBar(R.id.pw_c_bar, 1000, progress(c, cg), false)
            views.setTextViewText(
                R.id.pw_water_pct,
                context.getString(R.string.pw_pct, (progress(water, waterGoal) / 10))
            )
            setButtons(context, views)
        }
        return views
    }

    private fun progress(v: Double, goal: Double): Int =
        if (goal <= 0) 0 else (v / goal * 1000).coerceIn(0.0, 1000.0).roundToInt()

    private fun setButtons(context: Context, views: RemoteViews) {
        views.setOnClickPendingIntent(R.id.pw_btn_water, open(context, "water", 11))
        views.setOnClickPendingIntent(R.id.pw_btn_food, open(context, "nutrition", 12))
        views.setOnClickPendingIntent(R.id.pw_btn_weight, open(context, "weight", 13))
    }

    fun updateAll(context: Context) {
        val mgr = AppWidgetManager.getInstance(context)
        for ((cls, medium) in listOf(
            PitanieSmallWidget::class.java to false,
            PitanieMediumWidget::class.java to true
        )) {
            val ids = mgr.getAppWidgetIds(ComponentName(context, cls))
            for (id in ids) mgr.updateAppWidget(id, build(context, medium))
        }
    }
}

class PitanieSmallWidget : AppWidgetProvider() {
    override fun onUpdate(context: Context, mgr: AppWidgetManager, ids: IntArray) {
        for (id in ids) mgr.updateAppWidget(id, WidgetRenderer.build(context, false))
    }
}

class PitanieMediumWidget : AppWidgetProvider() {
    override fun onUpdate(context: Context, mgr: AppWidgetManager, ids: IntArray) {
        for (id in ids) mgr.updateAppWidget(id, WidgetRenderer.build(context, true))
    }
}
