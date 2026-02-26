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
      id: json['id'] as String? ?? '',
      summary: json['summary'] as String? ?? '',
      description: json['description'] as String? ?? '',
      startTime: DateTime.parse(json['start_time'] as String),
      endTime: DateTime.parse(json['end_time'] as String),
      allDay: json['all_day'] as bool? ?? false,
      colorHex: json['color_hex'] as String? ?? '#6C757D',
      providerColorId: json['provider_color_id'] as String?,
    );
  }
}
