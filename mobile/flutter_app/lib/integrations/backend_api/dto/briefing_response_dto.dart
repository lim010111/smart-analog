import 'json_contract.dart';

class BriefingResponseDto {
  const BriefingResponseDto({
    required this.provider,
    required this.generatedAt,
    required this.briefing,
    required this.eventCount,
    required this.disabled,
  });

  final String provider;
  final DateTime generatedAt;
  final String briefing;
  final int eventCount;
  final bool disabled;

  factory BriefingResponseDto.fromJson(Map<String, dynamic> json) {
    return BriefingResponseDto(
      provider: requireNonEmptyString(json, 'provider'),
      generatedAt: requireIsoDateTime(json, 'generated_at'),
      briefing: requireString(json, 'briefing'),
      eventCount: requireInt(json, 'event_count'),
      disabled: json['disabled'] is bool ? json['disabled'] as bool : false,
    );
  }
}

class BriefingTtsBase64ResponseDto {
  const BriefingTtsBase64ResponseDto({
    required this.audioBase64,
    required this.format,
    required this.mimeType,
  });

  final String audioBase64;
  final String format;
  final String mimeType;

  factory BriefingTtsBase64ResponseDto.fromJson(Map<String, dynamic> json) {
    return BriefingTtsBase64ResponseDto(
      audioBase64: requireNonEmptyString(json, 'audio_base64'),
      format: requireNonEmptyString(json, 'format'),
      mimeType: requireNonEmptyString(json, 'mime_type'),
    );
  }
}
