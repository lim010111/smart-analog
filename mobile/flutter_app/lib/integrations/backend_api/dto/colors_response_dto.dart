import 'color_rule_dto.dart';
import 'json_contract.dart';

class ColorPaletteResponseDto {
  const ColorPaletteResponseDto({
    required this.provider,
    required this.canWrite,
    required this.palette,
  });

  final String provider;
  final bool canWrite;
  final List<String> palette;

  factory ColorPaletteResponseDto.fromJson(Map<String, dynamic> json) {
    return ColorPaletteResponseDto(
      provider: requireNonEmptyString(json, 'provider'),
      canWrite: requireBool(json, 'can_write'),
      palette: requireStringList(json, 'palette'),
    );
  }
}

class ColorSchemaResponseDto {
  const ColorSchemaResponseDto({required this.provider, required this.rules});

  final String provider;
  final List<ColorRuleDto> rules;

  factory ColorSchemaResponseDto.fromJson(Map<String, dynamic> json) {
    final rulesJson = requireObjectList(json, 'rules');
    return ColorSchemaResponseDto(
      provider: requireNonEmptyString(json, 'provider'),
      rules: rulesJson.map(ColorRuleDto.fromJson).toList(),
    );
  }
}

class UpdateColorSchemaResponseDto {
  const UpdateColorSchemaResponseDto({
    required this.provider,
    required this.savedCount,
  });

  final String provider;
  final int savedCount;

  factory UpdateColorSchemaResponseDto.fromJson(Map<String, dynamic> json) {
    return UpdateColorSchemaResponseDto(
      provider: requireNonEmptyString(json, 'provider'),
      savedCount: requireInt(json, 'saved_count'),
    );
  }
}

class ApplyColorsResponseDto {
  const ApplyColorsResponseDto({
    required this.provider,
    required this.processed,
    required this.updated,
    required this.processedToday,
    required this.updatedToday,
    required this.backgroundStarted,
    required this.backgroundQueued,
  });

  final String provider;
  final int processed;
  final int updated;
  final int processedToday;
  final int updatedToday;
  final bool backgroundStarted;
  final bool backgroundQueued;

  factory ApplyColorsResponseDto.fromJson(Map<String, dynamic> json) {
    return ApplyColorsResponseDto(
      provider: requireNonEmptyString(json, 'provider'),
      processed: requireInt(json, 'processed'),
      updated: requireInt(json, 'updated'),
      processedToday: requireInt(json, 'processed_today'),
      updatedToday: requireInt(json, 'updated_today'),
      backgroundStarted: requireBool(json, 'background_started'),
      backgroundQueued: requireBool(json, 'background_queued'),
    );
  }
}

class ApplyColorsStatusResponseDto {
  const ApplyColorsStatusResponseDto({
    required this.provider,
    required this.running,
    required this.queued,
    required this.lastStartedAt,
    required this.lastFinishedAt,
    required this.lastProcessed,
    required this.lastUpdated,
    required this.lastError,
  });

  final String provider;
  final bool running;
  final bool queued;
  final String? lastStartedAt;
  final String? lastFinishedAt;
  final int lastProcessed;
  final int lastUpdated;
  final String lastError;

  factory ApplyColorsStatusResponseDto.fromJson(Map<String, dynamic> json) {
    return ApplyColorsStatusResponseDto(
      provider: requireNonEmptyString(json, 'provider'),
      running: requireBool(json, 'running'),
      queued: requireBool(json, 'queued'),
      lastStartedAt: optionalString(json, 'last_started_at'),
      lastFinishedAt: optionalString(json, 'last_finished_at'),
      lastProcessed: requireInt(json, 'last_processed'),
      lastUpdated: requireInt(json, 'last_updated'),
      lastError: requireString(json, 'last_error'),
    );
  }
}
