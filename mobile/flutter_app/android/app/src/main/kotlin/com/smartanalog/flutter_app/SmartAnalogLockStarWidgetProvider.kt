package com.smartanalog.flutter_app

import android.app.AlarmManager
import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.graphics.Color
import android.view.View
import android.widget.RemoteViews
import java.io.File
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import org.json.JSONArray
import org.json.JSONObject

class SmartAnalogLockStarWidgetProvider : AppWidgetProvider() {
    override fun onEnabled(context: Context) {
        super.onEnabled(context)
        scheduleMinuteRefresh(context)
    }

    override fun onDisabled(context: Context) {
        cancelMinuteRefresh(context)
        super.onDisabled(context)
    }

    override fun onDeleted(context: Context, appWidgetIds: IntArray) {
        super.onDeleted(context, appWidgetIds)
        val manager = AppWidgetManager.getInstance(context)
        val component = ComponentName(context, SmartAnalogLockStarWidgetProvider::class.java)
        if (manager.getAppWidgetIds(component).isEmpty()) {
            cancelMinuteRefresh(context)
        }
    }

    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action == minuteRefreshAction) {
            refreshAllWidgets(context)
            return
        }
        super.onReceive(context, intent)
    }

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
    ) {
        scheduleMinuteRefresh(context)
        appWidgetIds.forEach { appWidgetId ->
            updateWidget(context, appWidgetManager, appWidgetId)
        }
    }

    companion object {
        private const val snapshotFileName = "widget_snapshot_read_v1.json"
        private const val minuteRefreshAction =
            "com.smartanalog.flutter_app.action.WIDGET_LOCKSTAR_MINUTE_REFRESH"
        private const val minuteRefreshRequestCode = 32002
        private const val minuteIntervalMillis = 60_000L

        fun refreshAllWidgets(context: Context) {
            val appWidgetManager = AppWidgetManager.getInstance(context)
            val componentName = ComponentName(context, SmartAnalogLockStarWidgetProvider::class.java)
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
            val views =
                RemoteViews(context.packageName, R.layout.smart_analog_lockstar_appwidget)
            val snapshot = readSnapshot(context)
            val now = Date()

            val isLightTheme = snapshot?.theme == "light"
            val titleColor = if (isLightTheme) {
                Color.parseColor("#FF334155")
            } else {
                Color.parseColor("#FFCBD5E1")
            }
            val eventTextColor = if (isLightTheme) {
                Color.parseColor("#FF1E293B")
            } else {
                Color.parseColor("#FFD1D5DB")
            }

            views.setInt(
                R.id.lockstar_root,
                "setBackgroundResource",
                if (isLightTheme) {
                    R.drawable.widget_lockstar_background_light
                } else {
                    R.drawable.widget_lockstar_background
                },
            )

            views.setImageViewBitmap(
                R.id.lockstar_clock_bitmap,
                SmartAnalogAppWidgetProvider.renderClockBitmapForLockStar(
                    context = context,
                    now = now,
                    sizePx = 250,
                ),
            )
            views.setTextViewText(R.id.lockstar_event_list_title, "Today")
            views.setTextColor(R.id.lockstar_event_list_title, titleColor)

            val eventLines = buildMiniEventLines(snapshot?.events ?: emptyList())
            bindEventLine(
                views = views,
                rowViewId = R.id.lockstar_event_row_1,
                colorViewId = R.id.lockstar_event_color_1,
                textViewId = R.id.lockstar_event_item_1,
                line = eventLines.getOrNull(0),
                visible = true,
                textColor = eventTextColor,
            )
            bindEventLine(
                views = views,
                rowViewId = R.id.lockstar_event_row_2,
                colorViewId = R.id.lockstar_event_color_2,
                textViewId = R.id.lockstar_event_item_2,
                line = eventLines.getOrNull(1),
                visible = eventLines.size >= 2,
                textColor = eventTextColor,
            )
            bindEventLine(
                views = views,
                rowViewId = R.id.lockstar_event_row_3,
                colorViewId = R.id.lockstar_event_color_3,
                textViewId = R.id.lockstar_event_item_3,
                line = eventLines.getOrNull(2),
                visible = eventLines.size >= 3,
                textColor = eventTextColor,
            )

            val launchIntent = Intent(context, MainActivity::class.java).apply {
                flags =
                    Intent.FLAG_ACTIVITY_NEW_TASK or
                        Intent.FLAG_ACTIVITY_CLEAR_TOP or
                        Intent.FLAG_ACTIVITY_SINGLE_TOP
            }
            val flags = PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            val pendingIntent = PendingIntent.getActivity(context, 0, launchIntent, flags)
            views.setOnClickPendingIntent(R.id.lockstar_root, pendingIntent)

            appWidgetManager.updateAppWidget(appWidgetId, views)
        }

        private fun bindEventLine(
            views: RemoteViews,
            rowViewId: Int,
            colorViewId: Int,
            textViewId: Int,
            line: LockStarWidgetEventLine?,
            visible: Boolean,
            textColor: Int,
        ) {
            views.setViewVisibility(rowViewId, if (visible) View.VISIBLE else View.GONE)
            if (!visible) {
                return
            }

            val fallbackDotColor = Color.parseColor("#64748B")
            if (line == null) {
                views.setViewVisibility(colorViewId, View.GONE)
                views.setTextViewText(textViewId, "No events today")
                views.setTextColor(textViewId, textColor)
                return
            }

            views.setViewVisibility(colorViewId, View.VISIBLE)
            views.setTextViewText(colorViewId, "●")
            views.setTextColor(colorViewId, parseColor(line.colorHex, fallbackDotColor))
            views.setTextViewText(textViewId, line.text)
            views.setTextColor(textViewId, textColor)
        }

        private fun buildMiniEventLines(events: List<LockStarWidgetEventSummary>): List<LockStarWidgetEventLine> {
            if (events.isEmpty()) {
                return emptyList()
            }

            val sorted = events.sortedWith(
                compareBy<LockStarWidgetEventSummary>(
                    { if (it.allDay) 0 else 1 },
                    { it.startTime?.time ?: Long.MAX_VALUE },
                    { it.title.lowercase(Locale.getDefault()) },
                ),
            )

            return sorted.take(3).map { event ->
                if (event.allDay) {
                    LockStarWidgetEventLine(
                        text = "- All day - ${event.title}",
                        colorHex = event.colorHex,
                    )
                } else {
                    val start = event.startTime?.let(::formatTime24h) ?: "--:--"
                    val end = event.endTime?.let(::formatTime24h) ?: "--:--"
                    val timePart = if (start == end) start else "$start-$end"
                    LockStarWidgetEventLine(
                        text = "- $timePart - ${event.title}",
                        colorHex = event.colorHex,
                    )
                }
            }
        }

        private fun formatTime24h(date: Date): String {
            val formatter = SimpleDateFormat("HH:mm", Locale.getDefault())
            return formatter.format(date)
        }

        private fun readSnapshot(context: Context): LockStarWidgetSnapshotSummary? {
            val snapshotFile = File(context.filesDir, snapshotFileName)
            if (!snapshotFile.exists()) {
                return null
            }

            return runCatching {
                val root = JSONObject(snapshotFile.readText())
                val snapshot = root.optJSONObject("snapshot")
                val style = snapshot?.optJSONObject("style")
                val events = parseEvents(snapshot?.optJSONArray("events"))

                LockStarWidgetSnapshotSummary(
                    theme = style?.optString("theme", "dark") ?: "dark",
                    events = events,
                )
            }.getOrNull()
        }

        private fun parseEvents(eventsJson: JSONArray?): List<LockStarWidgetEventSummary> {
            if (eventsJson == null) {
                return emptyList()
            }

            val events = mutableListOf<LockStarWidgetEventSummary>()
            for (index in 0 until eventsJson.length()) {
                val item = eventsJson.optJSONObject(index) ?: continue
                val allDay = item.optBoolean("all_day", false)
                val start = parseIsoDateTime(item.optString("start_time"))
                val end = parseIsoDateTime(item.optString("end_time"))
                if (!allDay && (start == null || end == null)) {
                    continue
                }

                events.add(
                    LockStarWidgetEventSummary(
                        title = item.optString("title", "Untitled"),
                        startTime = start,
                        endTime = end,
                        allDay = allDay,
                        colorHex = item.optString("color_hex", "#64748B"),
                    ),
                )
            }
            return events
        }

        private fun parseIsoDateTime(value: String): Date? {
            if (value.isBlank()) {
                return null
            }

            val normalized = normalizeIso(value)
            val patterns = listOf(
                "yyyy-MM-dd'T'HH:mm:ss.SSSXXX",
                "yyyy-MM-dd'T'HH:mm:ssXXX",
                "yyyy-MM-dd'T'HH:mm:ss.SSS",
                "yyyy-MM-dd'T'HH:mm:ss",
            )
            for (pattern in patterns) {
                val formatter = SimpleDateFormat(pattern, Locale.US)
                formatter.isLenient = false
                val parsed = runCatching { formatter.parse(normalized) }.getOrNull()
                if (parsed != null) {
                    return parsed
                }
            }
            return null
        }

        private fun normalizeIso(value: String): String {
            val trimmed = value.trim()
            val fractionRegex = Regex("\\.(\\d{3})\\d+")
            val reducedFraction = fractionRegex.replace(trimmed, ".$1")

            if (reducedFraction.endsWith("Z")) {
                return reducedFraction.replace("Z", "+00:00")
            }
            return reducedFraction
        }

        private fun parseColor(value: String, fallback: Int): Int {
            return runCatching { Color.parseColor(value) }.getOrElse { fallback }
        }

        private fun scheduleMinuteRefresh(context: Context) {
            val alarmManager =
                context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
            val pendingIntent = minuteRefreshPendingIntent(context)
            alarmManager.cancel(pendingIntent)

            val now = System.currentTimeMillis()
            val firstTrigger = now - (now % minuteIntervalMillis) + minuteIntervalMillis
            alarmManager.setInexactRepeating(
                AlarmManager.RTC,
                firstTrigger,
                minuteIntervalMillis,
                pendingIntent,
            )
        }

        private fun cancelMinuteRefresh(context: Context) {
            val alarmManager =
                context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
            alarmManager.cancel(minuteRefreshPendingIntent(context))
        }

        private fun minuteRefreshPendingIntent(context: Context): PendingIntent {
            val intent =
                Intent(context, SmartAnalogLockStarWidgetProvider::class.java).apply {
                    action = minuteRefreshAction
                }
            val flags = PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            return PendingIntent.getBroadcast(
                context,
                minuteRefreshRequestCode,
                intent,
                flags,
            )
        }
    }
}

private data class LockStarWidgetSnapshotSummary(
    val theme: String,
    val events: List<LockStarWidgetEventSummary>,
)

private data class LockStarWidgetEventSummary(
    val title: String,
    val startTime: Date?,
    val endTime: Date?,
    val allDay: Boolean,
    val colorHex: String,
)

private data class LockStarWidgetEventLine(
    val text: String,
    val colorHex: String,
)
