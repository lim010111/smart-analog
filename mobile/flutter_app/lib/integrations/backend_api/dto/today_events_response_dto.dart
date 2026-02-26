import 'web_event_dto.dart';
import 'json_contract.dart';

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
    final eventsJson = requireObjectList(json, 'events');
    return TodayEventsResponseDto(
      provider: requireNonEmptyString(json, 'provider'),
      date: requireNonEmptyString(json, 'date'),
      count: requireInt(json, 'count'),
      events: eventsJson.map(WebEventDto.fromJson).toList(),
    );
  }
}
