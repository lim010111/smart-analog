package com.smartanalog.flutter_app

import android.app.AlarmManager
import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.Path
import android.graphics.RectF
import android.view.View
import android.widget.RemoteViews
import java.io.File
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import kotlin.math.cos
import kotlin.math.min
import kotlin.math.roundToInt
import kotlin.math.sin
import kotlin.math.sqrt
import org.json.JSONArray
import org.json.JSONObject

class SmartAnalogAppWidgetProvider : AppWidgetProvider() {
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
        val component = ComponentName(context, SmartAnalogAppWidgetProvider::class.java)
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
            "com.smartanalog.flutter_app.action.WIDGET_MINUTE_REFRESH"
        private const val minuteRefreshRequestCode = 32001
        private const val minuteIntervalMillis = 60_000L

        fun refreshAllWidgets(context: Context) {
            val appWidgetManager = AppWidgetManager.getInstance(context)
            val componentName = ComponentName(context, SmartAnalogAppWidgetProvider::class.java)
            val widgetIds = appWidgetManager.getAppWidgetIds(componentName)
            widgetIds.forEach { widgetId ->
                updateWidget(context, appWidgetManager, widgetId)
            }
        }

        fun renderClockBitmapForLockStar(
            context: Context,
            now: Date,
            sizePx: Int = 220,
        ): Bitmap {
            val snapshot = readSnapshot(context)
            return renderClockBitmap(
                snapshot = snapshot,
                now = now,
                width = sizePx,
                height = sizePx,
            )
        }

        private fun updateWidget(
            context: Context,
            appWidgetManager: AppWidgetManager,
            appWidgetId: Int,
        ) {
            val views = RemoteViews(context.packageName, R.layout.smart_analog_appwidget)
            val snapshot = readSnapshot(context)
            val now = Date()

            val titleText = snapshot?.let { "Smart Analog - ${it.date}" } ?: "Smart Analog"
            val subtitleText = snapshot?.let {
                "${it.timezone} | events ${it.eventCount}"
            } ?: "No snapshot yet"
            val isLightTheme = snapshot?.theme == "light"
            val backgroundColor = if (isLightTheme) {
                Color.parseColor("#FFF8FAFC")
            } else {
                Color.parseColor("#FF111827")
            }
            val titleColor = if (isLightTheme) {
                Color.parseColor("#FF0F172A")
            } else {
                Color.parseColor("#FFF8FAFC")
            }
            val subtitleColor = if (isLightTheme) {
                Color.parseColor("#FF334155")
            } else {
                Color.parseColor("#FF94A3B8")
            }
            val eventTextColor = if (isLightTheme) {
                Color.parseColor("#FF1E293B")
            } else {
                Color.parseColor("#FFD1D5DB")
            }

            views.setTextViewText(R.id.widget_title, titleText)
            views.setTextViewText(R.id.widget_subtitle, subtitleText)
            views.setTextViewText(R.id.widget_event_list_title, "Today")
            views.setTextColor(R.id.widget_title, titleColor)
            views.setTextColor(R.id.widget_subtitle, subtitleColor)
            views.setTextColor(R.id.widget_event_list_title, subtitleColor)
            views.setInt(R.id.widget_root, "setBackgroundColor", backgroundColor)

            val eventLines = buildMiniEventLines(snapshot?.events ?: emptyList())
            bindEventLine(
                views = views,
                rowViewId = R.id.widget_event_row_1,
                colorViewId = R.id.widget_event_color_1,
                textViewId = R.id.widget_event_item_1,
                line = eventLines.getOrNull(0),
                visible = true,
                textColor = eventTextColor,
            )
            bindEventLine(
                views = views,
                rowViewId = R.id.widget_event_row_2,
                colorViewId = R.id.widget_event_color_2,
                textViewId = R.id.widget_event_item_2,
                line = eventLines.getOrNull(1),
                visible = eventLines.size >= 2,
                textColor = eventTextColor,
            )
            bindEventLine(
                views = views,
                rowViewId = R.id.widget_event_row_3,
                colorViewId = R.id.widget_event_color_3,
                textViewId = R.id.widget_event_item_3,
                line = eventLines.getOrNull(2),
                visible = eventLines.size >= 3,
                textColor = eventTextColor,
            )

            views.setImageViewBitmap(R.id.widget_clock_bitmap, renderClockBitmap(snapshot, now))

            val launchIntent = Intent(context, MainActivity::class.java).apply {
                flags =
                    Intent.FLAG_ACTIVITY_NEW_TASK or
                        Intent.FLAG_ACTIVITY_CLEAR_TOP or
                        Intent.FLAG_ACTIVITY_SINGLE_TOP
            }
            val flags = PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            val pendingIntent = PendingIntent.getActivity(context, 0, launchIntent, flags)
            views.setOnClickPendingIntent(R.id.widget_root, pendingIntent)

            appWidgetManager.updateAppWidget(appWidgetId, views)
        }

        private fun bindEventLine(
            views: RemoteViews,
            rowViewId: Int,
            colorViewId: Int,
            textViewId: Int,
            line: WidgetEventLine?,
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

        private fun buildMiniEventLines(events: List<WidgetEventSummary>): List<WidgetEventLine> {
            if (events.isEmpty()) {
                return emptyList()
            }

            val sorted = events.sortedWith(
                compareBy<WidgetEventSummary>(
                    { if (it.allDay) 0 else 1 },
                    { it.startTime?.time ?: Long.MAX_VALUE },
                    { it.title.lowercase(Locale.getDefault()) },
                ),
            )

            return sorted.take(3).map(::formatMiniEventLine)
        }

        private fun formatMiniEventLine(event: WidgetEventSummary): WidgetEventLine {
            if (event.allDay) {
                return WidgetEventLine(
                    text = "- All day - ${event.title}",
                    colorHex = event.colorHex,
                )
            }

            val start = event.startTime?.let(::formatTime24h) ?: "--:--"
            val end = event.endTime?.let(::formatTime24h) ?: "--:--"
            val timePart = if (start == end) start else "$start-$end"
            return WidgetEventLine(
                text = "- $timePart - ${event.title}",
                colorHex = event.colorHex,
            )
        }

        private fun formatTime24h(date: Date): String {
            val formatter = SimpleDateFormat("HH:mm", Locale.getDefault())
            return formatter.format(date)
        }

        private fun readSnapshot(context: Context): WidgetSnapshotSummary? {
            val snapshotFile = File(context.filesDir, snapshotFileName)
            if (!snapshotFile.exists()) {
                return null
            }

            return runCatching {
                val root = JSONObject(snapshotFile.readText())
                val snapshot = root.optJSONObject("snapshot")
                val style = snapshot?.optJSONObject("style")
                val events = parseEvents(snapshot?.optJSONArray("events"))

                WidgetSnapshotSummary(
                    date = snapshot?.optString("date").orEmpty(),
                    timezone = snapshot?.optString("timezone").orEmpty(),
                    generatedAt = root.optString("generated_at"),
                    eventCount = events.size,
                    theme = style?.optString("theme", "dark") ?: "dark",
                    eventOpacity = style?.optDouble("event_opacity", 0.6)?.toFloat() ?: 0.6f,
                    events = events,
                )
            }.getOrNull()
        }

        private fun parseEvents(eventsJson: JSONArray?): List<WidgetEventSummary> {
            if (eventsJson == null) {
                return emptyList()
            }

            val events = mutableListOf<WidgetEventSummary>()
            for (index in 0 until eventsJson.length()) {
                val item = eventsJson.optJSONObject(index) ?: continue
                val allDay = item.optBoolean("all_day", false)
                val start = parseIsoDateTime(item.optString("start_time"))
                val end = parseIsoDateTime(item.optString("end_time"))
                if (!allDay && (start == null || end == null)) {
                    continue
                }

                events.add(
                    WidgetEventSummary(
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

        private fun renderClockBitmap(
            snapshot: WidgetSnapshotSummary?,
            now: Date,
            width: Int = 420,
            height: Int = 420,
        ): Bitmap {
            val bitmap = Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888)
            val canvas = Canvas(bitmap)

            val palette = if (snapshot?.theme == "light") {
                WidgetPalette(
                    face = Color.argb((0.6f * 255).roundToInt(), 255, 255, 255),
                    border = Color.argb((0.3f * 255).roundToInt(), 148, 163, 184),
                    tick = Color.parseColor("#334155"),
                    hand = Color.parseColor("#0F172A"),
                    number = Color.parseColor("#0F172A"),
                    second = Color.parseColor("#DC2626"),
                )
            } else {
                WidgetPalette(
                    face = Color.argb((0.4f * 255).roundToInt(), 18, 24, 38),
                    border = Color.argb((0.2f * 255).roundToInt(), 143, 166, 214),
                    tick = Color.parseColor("#CBD5E1"),
                    hand = Color.parseColor("#F8FAFC"),
                    number = Color.parseColor("#F8FAFC"),
                    second = Color.parseColor("#EF4444"),
                )
            }

            val shortest = min(width.toFloat(), height.toFloat())
            val scale = (shortest - 12f) / 200f
            val centerX = width / 2f
            val centerY = height / 2f
            val faceRadius = 95f * scale
            val pieRadius = 88f * scale
            val arcRadius = 94f * scale

            val faceFill = Paint(Paint.ANTI_ALIAS_FLAG).apply {
                color = palette.face
                style = Paint.Style.FILL
            }
            val faceBorder = Paint(Paint.ANTI_ALIAS_FLAG).apply {
                color = palette.border
                style = Paint.Style.STROKE
                strokeWidth = 1.5f
            }
            canvas.drawCircle(centerX, centerY, faceRadius, faceFill)
            canvas.drawCircle(centerX, centerY, faceRadius, faceBorder)

            val eventOpacityByte = eventOpacityToByte(snapshot?.eventOpacity ?: 0.6f)
            val allDayEvents = snapshot?.events?.filter { it.allDay } ?: emptyList()
            allDayEvents.forEachIndexed { index, event ->
                val spacing = 10f * scale
                val totalWidth = (allDayEvents.size - 1) * spacing
                val dotX = centerX + (-totalWidth / 2f) + index * spacing
                val dotY = centerY + (-103f * scale)
                val alpha = (eventOpacityByte / 255f).coerceIn(0.1f, 1f)
                val dotPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
                    color = withAlpha(parseColor(event.colorHex, Color.parseColor("#64748B")), alpha)
                    style = Paint.Style.FILL
                }
                canvas.drawCircle(dotX, dotY, 3.5f * scale, dotPaint)
            }

            val currentIsAm = extractHour(now) < 12
            val events = snapshot?.events ?: emptyList()
            for (event in events) {
                if (event.allDay) {
                    continue
                }
                val eventStart = event.startTime ?: continue
                val eventEnd = event.endTime ?: continue
                if (now.after(eventEnd)) {
                    continue
                }

                val isInProgress = !now.before(eventStart) && !now.after(eventEnd)
                val isCurrentCycle = isInProgress || (currentIsAm == (extractHour(eventStart) < 12))

                var startHour = (extractHour(eventStart) % 12) + (extractMinute(eventStart) / 60f)
                var startAngle = 90f - startHour * 30f
                var spanAngle = -((min(720f, minutesBetween(eventStart, eventEnd)) / 720f) * 360f)

                if (isInProgress) {
                    startHour =
                        (extractHour(now) % 12) + (extractMinute(now) / 60f) + (extractSecond(now) / 3600f)
                    startAngle = 90f - startHour * 30f
                    val remainingHours =
                        ((eventEnd.time - now.time) / 3600000f).coerceIn(0f, 12f)
                    spanAngle = -(remainingHours * 30f)
                }

                val startDeg = -startAngle
                val sweepDeg = -spanAngle
                val eventColor = parseColor(event.colorHex, Color.parseColor("#64748B"))
                val alphaBase = (eventOpacityByte / 255f).coerceIn(0.15f, 1f)

                if (kotlin.math.abs(sweepDeg) < 0.0001f) {
                    drawZeroDurationMarker(
                        canvas = canvas,
                        centerX = centerX,
                        centerY = centerY,
                        startDeg = startDeg,
                        isCurrentCycle = isCurrentCycle,
                        pieRadius = pieRadius,
                        arcRadius = arcRadius,
                        scale = scale,
                        color = withAlpha(
                            eventColor,
                            if (isCurrentCycle) {
                                if (isInProgress) alphaBase else alphaBase * 0.7f
                            } else {
                                alphaBase * 0.8f
                            },
                        ),
                    )
                    continue
                }

                if (isCurrentCycle) {
                    val pieRect = RectF(
                        centerX - pieRadius,
                        centerY - pieRadius,
                        centerX + pieRadius,
                        centerY + pieRadius,
                    )

                    val path = Path().apply {
                        moveTo(centerX, centerY)
                        arcTo(pieRect, startDeg, sweepDeg)
                        close()
                    }

                    val fillPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
                        color = withAlpha(eventColor, if (isInProgress) alphaBase else alphaBase * 0.45f)
                        style = Paint.Style.FILL
                    }
                    canvas.drawPath(path, fillPaint)

                    val strokePaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
                        color = eventColor
                        style = Paint.Style.STROKE
                        strokeWidth = 1.6f
                    }
                    canvas.drawArc(pieRect, startDeg, sweepDeg, false, strokePaint)
                } else {
                    val arcPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
                        color = withAlpha(eventColor, alphaBase * 0.6f)
                        style = Paint.Style.STROKE
                        strokeWidth = 4f
                        strokeCap = Paint.Cap.ROUND
                    }
                    val arcRect = RectF(
                        centerX - arcRadius,
                        centerY - arcRadius,
                        centerX + arcRadius,
                        centerY + arcRadius,
                    )
                    canvas.drawArc(arcRect, startDeg, sweepDeg, false, arcPaint)
                }
            }

            val majorTickPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
                color = palette.tick
                strokeWidth = 2f
            }
            val minorTickPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
                color = palette.tick
                strokeWidth = 1f
            }

            for (index in 0 until 12) {
                val angle = Math.toRadians((index * 30).toDouble())
                val startX = centerX + cos(angle).toFloat() * (85f * scale)
                val startY = centerY + sin(angle).toFloat() * (85f * scale)
                val endX = centerX + cos(angle).toFloat() * (90f * scale)
                val endY = centerY + sin(angle).toFloat() * (90f * scale)
                canvas.drawLine(startX, startY, endX, endY, majorTickPaint)
            }
            for (index in 0 until 48) {
                if (index % 4 == 0) {
                    continue
                }
                val angle = Math.toRadians((index * 7.5).toDouble())
                val startX = centerX + cos(angle).toFloat() * (88f * scale)
                val startY = centerY + sin(angle).toFloat() * (88f * scale)
                val endX = centerX + cos(angle).toFloat() * (90f * scale)
                val endY = centerY + sin(angle).toFloat() * (90f * scale)
                canvas.drawLine(startX, startY, endX, endY, minorTickPaint)
            }

            val hourValue = (extractHour(now) % 12) + (extractMinute(now) / 60f)
            val minuteValue = extractMinute(now) + (extractSecond(now) / 60f)
            val secondValue = extractSecond(now) + (extractMillisecond(now) / 1000f)

            drawTriangleHand(
                canvas = canvas,
                centerX = centerX,
                centerY = centerY,
                angleDeg = hourValue * 30f,
                leftX = -4f * scale,
                baseY = 8f * scale,
                rightX = 4f * scale,
                tipY = -50f * scale,
                color = palette.hand,
            )
            drawTriangleHand(
                canvas = canvas,
                centerX = centerX,
                centerY = centerY,
                angleDeg = minuteValue * 6f,
                leftX = -3f * scale,
                baseY = 8f * scale,
                rightX = 3f * scale,
                tipY = -75f * scale,
                color = palette.hand,
            )
            drawTriangleHand(
                canvas = canvas,
                centerX = centerX,
                centerY = centerY,
                angleDeg = secondValue * 6f,
                leftX = -1f * scale,
                baseY = 15f * scale,
                rightX = 1f * scale,
                tipY = -85f * scale,
                color = palette.second,
                visible = false,
            )

            canvas.drawCircle(
                centerX,
                centerY,
                3f * scale,
                Paint(Paint.ANTI_ALIAS_FLAG).apply {
                    color = palette.hand
                    style = Paint.Style.FILL
                },
            )

            val textPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
                color = palette.number
                textAlign = Paint.Align.CENTER
                textSize = (9f * scale).roundToInt().toFloat()
            }
            val baselineOffset = (textPaint.descent() + textPaint.ascent()) / 2f
            for (hour in 1..12) {
                val angle = Math.toRadians((hour * 30 + 270).toDouble())
                val x = centerX + (72f * scale * cos(angle).toFloat())
                val y = centerY + (72f * scale * sin(angle).toFloat()) - baselineOffset
                canvas.drawText(hour.toString(), x, y, textPaint)
            }

            return bitmap
        }

        private fun drawTriangleHand(
            canvas: Canvas,
            centerX: Float,
            centerY: Float,
            angleDeg: Float,
            leftX: Float,
            baseY: Float,
            rightX: Float,
            tipY: Float,
            color: Int,
            visible: Boolean = true,
        ) {
            if (!visible) {
                return
            }
            val path = Path().apply {
                moveTo(leftX, baseY)
                lineTo(rightX, baseY)
                lineTo(0f, tipY)
                close()
            }

            canvas.save()
            canvas.translate(centerX, centerY)
            canvas.rotate(angleDeg)
            canvas.drawPath(
                path,
                Paint(Paint.ANTI_ALIAS_FLAG).apply {
                    this.color = color
                    style = Paint.Style.FILL
                },
            )
            canvas.restore()
        }

        private fun drawZeroDurationMarker(
            canvas: Canvas,
            centerX: Float,
            centerY: Float,
            startDeg: Float,
            isCurrentCycle: Boolean,
            pieRadius: Float,
            arcRadius: Float,
            scale: Float,
            color: Int,
        ) {
            val angleRad = Math.toRadians(startDeg.toDouble())
            val unitX = cos(angleRad).toFloat()
            val unitY = sin(angleRad).toFloat()
            val innerRadius = if (isCurrentCycle) 8f * scale else arcRadius - (6f * scale)
            val outerRadius = if (isCurrentCycle) pieRadius else arcRadius + (6f * scale)

            val markerPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
                this.color = color
                style = Paint.Style.STROKE
                strokeWidth = if (isCurrentCycle) 2.6f * scale else 3.2f * scale
                strokeCap = Paint.Cap.ROUND
            }

            canvas.drawLine(
                centerX + unitX * innerRadius,
                centerY + unitY * innerRadius,
                centerX + unitX * outerRadius,
                centerY + unitY * outerRadius,
                markerPaint,
            )
        }

        private fun eventOpacityToByte(value: Float): Int {
            val normalized = if (value <= 1f) value.coerceIn(0f, 1f) else (value / 100f)
            return (normalized * 255f).roundToInt().coerceIn(0, 255)
        }

        private fun withAlpha(color: Int, opacity: Float): Int {
            val clamped = opacity.coerceIn(0f, 1f)
            return Color.argb(
                (clamped * 255f).roundToInt(),
                Color.red(color),
                Color.green(color),
                Color.blue(color),
            )
        }

        private fun parseColor(value: String, fallback: Int): Int {
            return runCatching { Color.parseColor(value) }.getOrElse { fallback }
        }

        private fun minutesBetween(start: Date, end: Date): Float {
            return ((end.time - start.time).toFloat() / 60000f).coerceAtLeast(0f)
        }

        private fun extractHour(date: Date): Int {
            val calendar = java.util.Calendar.getInstance()
            calendar.time = date
            return calendar.get(java.util.Calendar.HOUR_OF_DAY)
        }

        private fun extractMinute(date: Date): Int {
            val calendar = java.util.Calendar.getInstance()
            calendar.time = date
            return calendar.get(java.util.Calendar.MINUTE)
        }

        private fun extractSecond(date: Date): Int {
            val calendar = java.util.Calendar.getInstance()
            calendar.time = date
            return calendar.get(java.util.Calendar.SECOND)
        }

        private fun extractMillisecond(date: Date): Int {
            val calendar = java.util.Calendar.getInstance()
            calendar.time = date
            return calendar.get(java.util.Calendar.MILLISECOND)
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
            val intent = Intent(context, SmartAnalogAppWidgetProvider::class.java).apply {
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

private data class WidgetSnapshotSummary(
    val date: String,
    val timezone: String,
    val generatedAt: String,
    val eventCount: Int,
    val theme: String,
    val eventOpacity: Float,
    val events: List<WidgetEventSummary>,
)

private data class WidgetEventSummary(
    val title: String,
    val startTime: Date?,
    val endTime: Date?,
    val allDay: Boolean,
    val colorHex: String,
)

private data class WidgetEventLine(
    val text: String,
    val colorHex: String,
)

private data class WidgetPalette(
    val face: Int,
    val border: Int,
    val tick: Int,
    val hand: Int,
    val number: Int,
    val second: Int,
)
