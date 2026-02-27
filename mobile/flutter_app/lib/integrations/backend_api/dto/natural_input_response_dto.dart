import 'json_contract.dart';
import 'web_event_dto.dart';

class NaturalParseResultDto {
  const NaturalParseResultDto({
    required this.intent,
    required this.title,
    required this.startTime,
    required this.endTime,
    required this.allDay,
    required this.confidence,
    required this.note,
  });

  final String intent;
  final String? title;
  final String? startTime;
  final String? endTime;
  final bool allDay;
  final double confidence;
  final String? note;

  factory NaturalParseResultDto.fromJson(Map<String, dynamic> json) {
    final confidenceRaw = json['confidence'];
    if (confidenceRaw is! num) {
      throw const FormatException(
        'Missing or invalid "confidence" in response payload.',
      );
    }

    return NaturalParseResultDto(
      intent: requireNonEmptyString(json, 'intent'),
      title: optionalString(json, 'title'),
      startTime: optionalString(json, 'start_time'),
      endTime: optionalString(json, 'end_time'),
      allDay: requireBool(json, 'all_day'),
      confidence: confidenceRaw.toDouble(),
      note: optionalString(json, 'note'),
    );
  }
}

class NaturalParseResponseDto {
  const NaturalParseResponseDto({
    required this.provider,
    required this.ready,
    required this.reason,
    required this.result,
  });

  final String provider;
  final bool ready;
  final String? reason;
  final NaturalParseResultDto? result;

  factory NaturalParseResponseDto.fromJson(Map<String, dynamic> json) {
    final resultJson = json['result'];
    return NaturalParseResponseDto(
      provider: requireNonEmptyString(json, 'provider'),
      ready: requireBool(json, 'ready'),
      reason: optionalString(json, 'reason'),
      result: resultJson is Map<String, dynamic>
          ? NaturalParseResultDto.fromJson(resultJson)
          : null,
    );
  }
}

class NaturalCreateResponseDto {
  const NaturalCreateResponseDto({
    required this.provider,
    required this.parsed,
    required this.created,
  });

  final String provider;
  final NaturalParseResultDto parsed;
  final WebEventDto? created;

  factory NaturalCreateResponseDto.fromJson(Map<String, dynamic> json) {
    final parsedJson = json['parsed'];
    if (parsedJson is! Map<String, dynamic>) {
      throw const FormatException(
        'Missing or invalid "parsed" in response payload.',
      );
    }

    final createdJson = json['created'];
    return NaturalCreateResponseDto(
      provider: requireNonEmptyString(json, 'provider'),
      parsed: NaturalParseResultDto.fromJson(parsedJson),
      created: createdJson is Map<String, dynamic>
          ? WebEventDto.fromJson(createdJson)
          : null,
    );
  }
}
