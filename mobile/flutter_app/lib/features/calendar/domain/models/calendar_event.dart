class CalendarEvent {
  const CalendarEvent({
    required this.id,
    required this.title,
    required this.description,
    required this.startTime,
    required this.endTime,
    required this.allDay,
    required this.colorHex,
    required this.provider,
    this.providerColorId,
  });

  final String id;
  final String title;
  final String description;
  final DateTime startTime;
  final DateTime endTime;
  final bool allDay;
  final String colorHex;
  final String provider;
  final String? providerColorId;

  CalendarEvent copyWith({
    String? id,
    String? title,
    String? description,
    DateTime? startTime,
    DateTime? endTime,
    bool? allDay,
    String? colorHex,
    String? provider,
    String? providerColorId,
  }) {
    return CalendarEvent(
      id: id ?? this.id,
      title: title ?? this.title,
      description: description ?? this.description,
      startTime: startTime ?? this.startTime,
      endTime: endTime ?? this.endTime,
      allDay: allDay ?? this.allDay,
      colorHex: colorHex ?? this.colorHex,
      provider: provider ?? this.provider,
      providerColorId: providerColorId ?? this.providerColorId,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'description': description,
      'start_time': startTime.toIso8601String(),
      'end_time': endTime.toIso8601String(),
      'all_day': allDay,
      'color_hex': colorHex,
      'provider': provider,
      'provider_color_id': providerColorId,
    };
  }

  factory CalendarEvent.fromJson(Map<String, dynamic> json) {
    return CalendarEvent(
      id: json['id'] as String? ?? '',
      title: json['title'] as String? ?? '',
      description: json['description'] as String? ?? '',
      startTime: DateTime.parse(json['start_time'] as String),
      endTime: DateTime.parse(json['end_time'] as String),
      allDay: json['all_day'] as bool? ?? false,
      colorHex: json['color_hex'] as String? ?? '#6C757D',
      provider: json['provider'] as String? ?? 'local',
      providerColorId: json['provider_color_id'] as String?,
    );
  }
}
