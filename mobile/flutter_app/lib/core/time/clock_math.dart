import '../../features/calendar/domain/models/calendar_event.dart';
import '../../features/calendar/domain/models/widget_snapshot.dart';

double minutesSinceMidnight(DateTime value) {
  return value.hour * 60 + value.minute + value.second / 60.0;
}

double minuteOfDayToClockAngle(double minuteOfDay) {
  final normalized = minuteOfDay % 720.0;
  return (normalized / 720.0) * 360.0 - 90.0;
}

List<WidgetSegment> buildClockSegments({
  required List<CalendarEvent> events,
  required DateTime dayStart,
  required DateTime dayEnd,
}) {
  final segments = <WidgetSegment>[];

  for (final event in events) {
    if (event.allDay) {
      continue;
    }

    final rawDurationMs =
        event.endTime.millisecondsSinceEpoch -
        event.startTime.millisecondsSinceEpoch;
    if (rawDurationMs < 0) {
      continue;
    }

    final isInstantEvent = rawDurationMs == 0;
    if (isInstantEvent &&
        (event.startTime.isBefore(dayStart) ||
            !event.startTime.isBefore(dayEnd))) {
      continue;
    }

    final start = event.startTime.isBefore(dayStart)
        ? dayStart
        : event.startTime;
    final end = event.endTime.isAfter(dayEnd) ? dayEnd : event.endTime;

    if (!isInstantEvent && !end.isAfter(start)) {
      continue;
    }

    final startMinute = minutesSinceMidnight(start);
    final sweepMinute = isInstantEvent
        ? 0.0
        : minutesSinceMidnight(end) - startMinute;

    final sweepAngle = (sweepMinute / 720.0) * 360.0;
    if (sweepAngle < 0) {
      continue;
    }

    segments.add(
      WidgetSegment(
        eventId: event.id,
        startAngleDeg: minuteOfDayToClockAngle(startMinute),
        sweepAngleDeg: sweepAngle,
        colorHex: event.colorHex,
      ),
    );
  }

  return segments;
}
