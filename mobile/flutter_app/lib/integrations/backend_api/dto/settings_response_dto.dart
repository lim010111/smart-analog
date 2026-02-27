import 'json_contract.dart';

class SettingsResponseDto {
  const SettingsResponseDto({
    required this.theme,
    required this.eventOpacity,
    required this.clockOpacity,
    required this.briefingEnabled,
    required this.briefingTtsEnabled,
    required this.widgetPinned,
  });

  final String theme;
  final int eventOpacity;
  final int clockOpacity;
  final bool briefingEnabled;
  final bool briefingTtsEnabled;
  final bool widgetPinned;

  factory SettingsResponseDto.fromJson(Map<String, dynamic> json) {
    return SettingsResponseDto(
      theme: requireNonEmptyString(json, 'theme'),
      eventOpacity: requireInt(json, 'event_opacity'),
      clockOpacity: requireInt(json, 'clock_opacity'),
      briefingEnabled: requireBool(json, 'briefing_enabled'),
      briefingTtsEnabled: requireBool(json, 'briefing_tts_enabled'),
      widgetPinned: requireBool(json, 'widget_pinned'),
    );
  }
}
