import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_app/features/calendar/application/widget_snapshot_builder.dart';
import 'package:flutter_app/features/calendar/domain/models/calendar_event.dart';

void main() {
  test('build creates snapshot with clock segment for timed event', () {
    final now = DateTime(2026, 3, 1, 10, 0, 0);
    final events = <CalendarEvent>[
      CalendarEvent(
        id: 'event-1',
        title: 'Standup',
        description: 'Daily team sync',
        startTime: DateTime(2026, 3, 1, 10, 30, 0),
        endTime: DateTime(2026, 3, 1, 11, 0, 0),
        allDay: false,
        colorHex: '#3A86FF',
        provider: 'google',
      ),
    ];

    final snapshot = const WidgetSnapshotBuilder().build(
      now: now,
      timezone: 'Asia/Seoul',
      events: events,
    );

    expect(snapshot.version, 1);
    expect(snapshot.date, '2026-03-01');
    expect(snapshot.events.length, 1);
    expect(snapshot.segments.length, 1);
    expect(snapshot.segments.first.eventId, 'event-1');
    expect(snapshot.segments.first.startAngleDeg, closeTo(225.0, 0.001));
    expect(snapshot.segments.first.sweepAngleDeg, closeTo(15.0, 0.001));
  });

  test('build ignores all-day events when creating clock segments', () {
    final now = DateTime(2026, 3, 1, 10, 0, 0);
    final events = <CalendarEvent>[
      CalendarEvent(
        id: 'event-all-day',
        title: 'Holiday',
        description: 'All day event',
        startTime: DateTime(2026, 3, 1, 0, 0, 0),
        endTime: DateTime(2026, 3, 1, 23, 59, 59),
        allDay: true,
        colorHex: '#FF006E',
        provider: 'google',
      ),
    ];

    final snapshot = const WidgetSnapshotBuilder().build(
      now: now,
      timezone: 'Asia/Seoul',
      events: events,
    );

    expect(snapshot.events.length, 1);
    expect(snapshot.segments, isEmpty);
  });
}
