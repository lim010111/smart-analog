import 'json_contract.dart';

class SettingsResponseDto {
  const SettingsResponseDto({
    required this.theme,
    required this.widgetTheme,
    required this.eventOpacity,
    required this.clockOpacity,
    required this.briefingEnabled,
    required this.briefingTtsEnabled,
  });

  final String theme;
  final String widgetTheme;
  final int eventOpacity;
  final int clockOpacity;
  final bool briefingEnabled;
  final bool briefingTtsEnabled;

  factory SettingsResponseDto.fromJson(Map<String, dynamic> json) {
    final theme = requireNonEmptyString(json, 'theme');
    final widgetThemeRaw = optionalString(json, 'widget_theme')?.trim();
    return SettingsResponseDto(
      theme: theme,
      widgetTheme: widgetThemeRaw != null && widgetThemeRaw.isNotEmpty
          ? widgetThemeRaw
          : theme,
      eventOpacity: requireInt(json, 'event_opacity'),
      clockOpacity: requireInt(json, 'clock_opacity'),
      briefingEnabled: requireBool(json, 'briefing_enabled'),
      briefingTtsEnabled: requireBool(json, 'briefing_tts_enabled'),
    );
  }
}
