import '../../../integrations/backend_api/api_client.dart';
import '../../../integrations/backend_api/dto/apple_credentials_response_dto.dart';
import '../../../integrations/backend_api/dto/briefing_response_dto.dart';
import '../../../integrations/backend_api/dto/color_rule_dto.dart';
import '../../../integrations/backend_api/dto/colors_response_dto.dart';
import '../../../integrations/backend_api/dto/create_event_response_dto.dart';
import '../../../integrations/backend_api/dto/google_auth_url_response_dto.dart';
import '../../../integrations/backend_api/dto/natural_input_response_dto.dart';
import '../../../integrations/backend_api/dto/provider_auth_response_dto.dart';
import '../../../integrations/backend_api/dto/provider_status_dto.dart';
import '../../../integrations/backend_api/dto/providers_response_dto.dart';
import '../../../integrations/backend_api/dto/settings_response_dto.dart';
import '../domain/models/calendar_event.dart';

class CalendarEventsRepository {
  CalendarEventsRepository({required BackendApiClient apiClient})
    : _apiClient = apiClient;

  final BackendApiClient _apiClient;

  Future<List<CalendarEvent>> fetchTodayEvents({
    String provider = 'google',
    int maxResults = 20,
    DateTime? date,
    bool applyColors = false,
  }) async {
    final response = await _apiClient.fetchTodayEvents(
      provider: provider,
      maxResults: maxResults,
      date: date,
      applyColors: applyColors,
    );

    return response.events
        .map(
          (dto) => CalendarEvent(
            id: dto.id,
            title: dto.summary,
            description: dto.description,
            startTime: dto.startTime.toLocal(),
            endTime: dto.endTime.toLocal(),
            allDay: dto.allDay,
            colorHex: dto.colorHex.isEmpty ? '#6C757D' : dto.colorHex,
            provider: response.provider,
            providerColorId: dto.providerColorId,
          ),
        )
        .toList();
  }

  Future<ProvidersResponseDto> fetchProviders() {
    return _apiClient.fetchProviders();
  }

  Future<ProviderStatusDto> fetchProviderStatus({
    required String provider,
    bool includeIdentity = false,
  }) {
    return _apiClient.fetchProviderStatus(
      provider: provider,
      includeIdentity: includeIdentity,
    );
  }

  Future<GoogleAuthUrlResponseDto> fetchGoogleAuthUrl({
    String? mobileCallback,
  }) {
    return _apiClient.fetchGoogleAuthUrl(mobileCallback: mobileCallback);
  }

  Future<AppleCredentialsResponseDto> setAppleCredentials({
    required String appleId,
    required String appPassword,
  }) {
    return _apiClient.setAppleCredentials(
      appleId: appleId,
      appPassword: appPassword,
    );
  }

  Future<ProviderAuthResponseDto> authenticateProvider({
    required String provider,
  }) {
    return _apiClient.authenticateProvider(provider: provider);
  }

  Future<ProviderLogoutResponseDto> logoutProvider({required String provider}) {
    return _apiClient.logoutProvider(provider: provider);
  }

  Future<SettingsResponseDto> fetchSettings() {
    return _apiClient.fetchSettings();
  }

  Future<SettingsResponseDto> updateSettings({
    required String theme,
    required String widgetTheme,
    required int eventOpacity,
    required int clockOpacity,
    required bool briefingEnabled,
    required bool briefingTtsEnabled,
  }) {
    return _apiClient.updateSettings(
      theme: theme,
      widgetTheme: widgetTheme,
      eventOpacity: eventOpacity,
      clockOpacity: clockOpacity,
      briefingEnabled: briefingEnabled,
      briefingTtsEnabled: briefingTtsEnabled,
    );
  }

  Future<CreateEventResponseDto> createEvent({
    required String provider,
    required String summary,
    required String startTime,
    required String endTime,
    required bool allDay,
  }) {
    return _apiClient.createEvent(
      provider: provider,
      summary: summary,
      startTime: startTime,
      endTime: endTime,
      allDay: allDay,
    );
  }

  Future<NaturalParseResponseDto> parseNaturalInput({
    required String provider,
    required String text,
  }) {
    return _apiClient.parseNaturalInput(provider: provider, text: text);
  }

  Future<NaturalCreateResponseDto> createEventFromNaturalInput({
    required String provider,
    required String text,
  }) {
    return _apiClient.createEventFromNaturalInput(
      provider: provider,
      text: text,
    );
  }

  Future<BriefingResponseDto> fetchTodayBriefing({
    required String provider,
    int maxResults = 20,
    bool force = true,
  }) {
    return _apiClient.fetchTodayBriefing(
      provider: provider,
      maxResults: maxResults,
      force: force,
    );
  }

  Future<BriefingTtsBase64ResponseDto> generateBriefingTtsBase64({
    required String text,
    String responseFormat = 'wav',
    String? voice,
    String? model,
    String? instructions,
  }) {
    return _apiClient.generateBriefingTtsBase64(
      text: text,
      responseFormat: responseFormat,
      voice: voice,
      model: model,
      instructions: instructions,
    );
  }

  Future<BriefingTtsBinaryResponse> generateBriefingTtsBinary({
    required String text,
    String responseFormat = 'wav',
    String? voice,
    String? model,
    String? instructions,
  }) {
    return _apiClient.generateBriefingTtsBinary(
      text: text,
      responseFormat: responseFormat,
      voice: voice,
      model: model,
      instructions: instructions,
    );
  }

  Future<ColorPaletteResponseDto> fetchColorPalette({
    required String provider,
  }) {
    return _apiClient.fetchColorPalette(provider: provider);
  }

  Future<ColorSchemaResponseDto> fetchColorSchema({required String provider}) {
    return _apiClient.fetchColorSchema(provider: provider);
  }

  Future<UpdateColorSchemaResponseDto> updateColorSchema({
    required String provider,
    required List<ColorRuleDto> rules,
  }) {
    return _apiClient.updateColorSchema(provider: provider, rules: rules);
  }

  Future<ApplyColorsResponseDto> applyColorsToAll({
    required String provider,
    int? maxResults,
    int pageSize = 250,
  }) {
    return _apiClient.applyColorsToAll(
      provider: provider,
      maxResults: maxResults,
      pageSize: pageSize,
    );
  }

  Future<ApplyColorsStatusResponseDto> fetchApplyColorsStatus({
    required String provider,
  }) {
    return _apiClient.fetchApplyColorsStatus(provider: provider);
  }

  void dispose() {
    _apiClient.dispose();
  }
}
