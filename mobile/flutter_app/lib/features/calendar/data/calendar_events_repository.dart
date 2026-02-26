import '../../../integrations/backend_api/api_client.dart';
import '../../../integrations/backend_api/dto/google_auth_url_response_dto.dart';
import '../../../integrations/backend_api/dto/provider_status_dto.dart';
import '../../../integrations/backend_api/dto/providers_response_dto.dart';
import '../domain/models/calendar_event.dart';

class CalendarEventsRepository {
  CalendarEventsRepository({required BackendApiClient apiClient})
    : _apiClient = apiClient;

  final BackendApiClient _apiClient;

  Future<List<CalendarEvent>> fetchTodayEvents({
    String provider = 'google',
    int maxResults = 20,
    DateTime? date,
  }) async {
    final response = await _apiClient.fetchTodayEvents(
      provider: provider,
      maxResults: maxResults,
      date: date,
    );

    return response.events
        .map(
          (dto) => CalendarEvent(
            id: dto.id,
            title: dto.summary,
            description: dto.description,
            startTime: dto.startTime,
            endTime: dto.endTime,
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

  Future<ProviderStatusDto> fetchProviderStatus({required String provider}) {
    return _apiClient.fetchProviderStatus(provider: provider);
  }

  Future<GoogleAuthUrlResponseDto> fetchGoogleAuthUrl() {
    return _apiClient.fetchGoogleAuthUrl();
  }

  void dispose() {
    _apiClient.dispose();
  }
}
