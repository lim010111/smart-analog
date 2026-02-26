import 'calendar_event.dart';

class WidgetClockValue {
  const WidgetClockValue({
    required this.hour,
    required this.minute,
    required this.second,
  });

  final int hour;
  final int minute;
  final int second;

  Map<String, dynamic> toJson() {
    return {'hour': hour, 'minute': minute, 'second': second};
  }

  factory WidgetClockValue.fromJson(Map<String, dynamic> json) {
    return WidgetClockValue(
      hour: json['hour'] as int? ?? 0,
      minute: json['minute'] as int? ?? 0,
      second: json['second'] as int? ?? 0,
    );
  }
}

class WidgetStyle {
  const WidgetStyle({
    required this.theme,
    required this.clockOpacity,
    required this.eventOpacity,
    required this.showSecondHand,
  });

  final String theme;
  final double clockOpacity;
  final double eventOpacity;
  final bool showSecondHand;

  Map<String, dynamic> toJson() {
    return {
      'theme': theme,
      'clock_opacity': clockOpacity,
      'event_opacity': eventOpacity,
      'show_second_hand': showSecondHand,
    };
  }

  factory WidgetStyle.fromJson(Map<String, dynamic> json) {
    return WidgetStyle(
      theme: json['theme'] as String? ?? 'dark',
      clockOpacity: (json['clock_opacity'] as num?)?.toDouble() ?? 1.0,
      eventOpacity: (json['event_opacity'] as num?)?.toDouble() ?? 0.6,
      showSecondHand: json['show_second_hand'] as bool? ?? false,
    );
  }
}

class WidgetSegment {
  const WidgetSegment({
    required this.eventId,
    required this.startAngleDeg,
    required this.sweepAngleDeg,
    required this.colorHex,
  });

  final String eventId;
  final double startAngleDeg;
  final double sweepAngleDeg;
  final String colorHex;

  Map<String, dynamic> toJson() {
    return {
      'event_id': eventId,
      'start_angle_deg': startAngleDeg,
      'sweep_angle_deg': sweepAngleDeg,
      'color_hex': colorHex,
    };
  }

  factory WidgetSegment.fromJson(Map<String, dynamic> json) {
    return WidgetSegment(
      eventId: json['event_id'] as String? ?? '',
      startAngleDeg: (json['start_angle_deg'] as num?)?.toDouble() ?? 0.0,
      sweepAngleDeg: (json['sweep_angle_deg'] as num?)?.toDouble() ?? 0.0,
      colorHex: json['color_hex'] as String? ?? '#6C757D',
    );
  }
}

class WidgetSnapshot {
  const WidgetSnapshot({
    required this.version,
    required this.generatedAt,
    required this.timezone,
    required this.date,
    required this.clock,
    required this.style,
    required this.events,
    required this.segments,
  });

  final int version;
  final DateTime generatedAt;
  final String timezone;
  final String date;
  final WidgetClockValue clock;
  final WidgetStyle style;
  final List<CalendarEvent> events;
  final List<WidgetSegment> segments;

  Map<String, dynamic> toJson() {
    return {
      'version': version,
      'generated_at': generatedAt.toIso8601String(),
      'timezone': timezone,
      'date': date,
      'clock': clock.toJson(),
      'style': style.toJson(),
      'events': events.map((event) => event.toJson()).toList(),
      'segments': segments.map((segment) => segment.toJson()).toList(),
    };
  }

  factory WidgetSnapshot.fromJson(Map<String, dynamic> json) {
    final clockJson =
        json['clock'] as Map<String, dynamic>? ?? <String, dynamic>{};
    final styleJson =
        json['style'] as Map<String, dynamic>? ?? <String, dynamic>{};

    final eventsJson = json['events'] as List<dynamic>? ?? <dynamic>[];
    final segmentsJson = json['segments'] as List<dynamic>? ?? <dynamic>[];

    return WidgetSnapshot(
      version: json['version'] as int? ?? 1,
      generatedAt: DateTime.parse(json['generated_at'] as String),
      timezone: json['timezone'] as String? ?? 'UTC',
      date: json['date'] as String? ?? '',
      clock: WidgetClockValue.fromJson(clockJson),
      style: WidgetStyle.fromJson(styleJson),
      events: eventsJson
          .whereType<Map<String, dynamic>>()
          .map(CalendarEvent.fromJson)
          .toList(),
      segments: segmentsJson
          .whereType<Map<String, dynamic>>()
          .map(WidgetSegment.fromJson)
          .toList(),
    );
  }
}
