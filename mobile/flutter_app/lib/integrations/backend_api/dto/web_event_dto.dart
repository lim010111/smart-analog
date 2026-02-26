import 'json_contract.dart';

class WebEventDto {
  const WebEventDto({
    required this.id,
    required this.summary,
    required this.description,
    required this.startTime,
    required this.endTime,
    required this.allDay,
    required this.colorHex,
    required this.providerColorId,
  });

  final String id;
  final String summary;
  final String description;
  final DateTime startTime;
  final DateTime endTime;
  final bool allDay;
  final String colorHex;
  final String? providerColorId;

  factory WebEventDto.fromJson(Map<String, dynamic> json) {
    return WebEventDto(
      id: requireNonEmptyString(json, 'id'),
      summary: requireString(json, 'summary'),
      description: requireString(json, 'description'),
      startTime: requireIsoDateTime(json, 'start_time'),
      endTime: requireIsoDateTime(json, 'end_time'),
      allDay: requireBool(json, 'all_day'),
      colorHex: requireNonEmptyString(json, 'color_hex'),
      providerColorId: optionalString(json, 'provider_color_id'),
    );
  }
}
