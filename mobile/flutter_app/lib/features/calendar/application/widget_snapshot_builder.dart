import '../../../core/time/clock_math.dart';
import '../domain/models/calendar_event.dart';
import '../domain/models/widget_snapshot.dart';

class WidgetSnapshotBuilder {
  const WidgetSnapshotBuilder();

  WidgetSnapshot build({
    required DateTime now,
    required String timezone,
    required List<CalendarEvent> events,
    String theme = 'dark',
    double clockOpacity = 1.0,
    double eventOpacity = 0.6,
    bool showSecondHand = false,
  }) {
    final dayStart = DateTime(now.year, now.month, now.day);
    final dayEnd = dayStart.add(const Duration(days: 1));

    final segments = buildClockSegments(
      events: events,
      dayStart: dayStart,
      dayEnd: dayEnd,
    );

    return WidgetSnapshot(
      version: 1,
      generatedAt: now,
      timezone: timezone,
      date: _isoDate(now),
      clock: WidgetClockValue(
        hour: now.hour,
        minute: now.minute,
        second: now.second,
      ),
      style: WidgetStyle(
        theme: theme,
        clockOpacity: clockOpacity,
        eventOpacity: eventOpacity,
        showSecondHand: showSecondHand,
      ),
      events: events,
      segments: segments,
    );
  }

  String _isoDate(DateTime value) {
    final year = value.year.toString().padLeft(4, '0');
    final month = value.month.toString().padLeft(2, '0');
    final day = value.day.toString().padLeft(2, '0');
    return '$year-$month-$day';
  }
}
