package com.smartanalog.flutter_app

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.widget.RemoteViews
import org.json.JSONObject
import java.io.File

class SmartAnalogAppWidgetProvider : AppWidgetProvider() {
    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
    ) {
        appWidgetIds.forEach { appWidgetId ->
            updateWidget(context, appWidgetManager, appWidgetId)
        }
    }

    companion object {
        private const val snapshotFileName = "widget_snapshot_read_v1.json"

        fun refreshAllWidgets(context: Context) {
            val appWidgetManager = AppWidgetManager.getInstance(context)
            val componentName = ComponentName(context, SmartAnalogAppWidgetProvider::class.java)
            val widgetIds = appWidgetManager.getAppWidgetIds(componentName)
            widgetIds.forEach { widgetId ->
                updateWidget(context, appWidgetManager, widgetId)
            }
        }

        private fun updateWidget(
            context: Context,
            appWidgetManager: AppWidgetManager,
            appWidgetId: Int,
        ) {
            val views = RemoteViews(context.packageName, R.layout.smart_analog_appwidget)
            val snapshot = readSnapshot(context)

            val titleText = snapshot?.let { "Smart Analog - ${it.date}" } ?: "Smart Analog"
            val subtitleText = snapshot?.let {
                "${it.timezone} | events ${it.eventCount} | generated ${it.generatedAt}"
            } ?: "No snapshot yet"

            views.setTextViewText(R.id.widget_title, titleText)
            views.setTextViewText(R.id.widget_subtitle, subtitleText)

            val launchIntent = Intent(context, MainActivity::class.java)
            val flags = PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            val pendingIntent = PendingIntent.getActivity(context, 0, launchIntent, flags)
            views.setOnClickPendingIntent(R.id.widget_root, pendingIntent)

            appWidgetManager.updateAppWidget(appWidgetId, views)
        }

        private fun readSnapshot(context: Context): WidgetSnapshotSummary? {
            val snapshotFile = File(context.filesDir, snapshotFileName)
            if (!snapshotFile.exists()) {
                return null
            }

            return runCatching {
                val root = JSONObject(snapshotFile.readText())
                val snapshot = root.optJSONObject("snapshot")
                WidgetSnapshotSummary(
                    date = snapshot?.optString("date").orEmpty(),
                    timezone = snapshot?.optString("timezone").orEmpty(),
                    generatedAt = root.optString("generated_at"),
                    eventCount = snapshot?.optJSONArray("events")?.length() ?: 0,
                )
            }.getOrNull()
        }
    }
}

private data class WidgetSnapshotSummary(
    val date: String,
    val timezone: String,
    val generatedAt: String,
    val eventCount: Int,
)
