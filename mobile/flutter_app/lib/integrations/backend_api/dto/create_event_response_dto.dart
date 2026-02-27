import 'json_contract.dart';
import 'web_event_dto.dart';

class CreateEventResponseDto {
  const CreateEventResponseDto({required this.provider, required this.event});

  final String provider;
  final WebEventDto event;

  factory CreateEventResponseDto.fromJson(Map<String, dynamic> json) {
    final eventJson = json['event'];
    if (eventJson is! Map<String, dynamic>) {
      throw const FormatException(
        'Missing or invalid "event" in response payload.',
      );
    }
    return CreateEventResponseDto(
      provider: requireNonEmptyString(json, 'provider'),
      event: WebEventDto.fromJson(eventJson),
    );
  }
}
