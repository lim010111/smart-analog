import 'web_event_dto.dart';

class TodayEventsResponseDto {
  const TodayEventsResponseDto({
    required this.provider,
    required this.date,
    required this.count,
    required this.events,
  });

  final String provider;
  final String date;
  final int count;
  final List<WebEventDto> events;

  factory TodayEventsResponseDto.fromJson(Map<String, dynamic> json) {
    final eventsJson = json['events'] as List<dynamic>? ?? <dynamic>[];
    return TodayEventsResponseDto(
      provider: json['provider'] as String? ?? 'google',
      date: json['date'] as String? ?? '',
      count: json['count'] as int? ?? 0,
      events: eventsJson
          .whereType<Map<String, dynamic>>()
          .map(WebEventDto.fromJson)
          .toList(),
    );
  }
}
