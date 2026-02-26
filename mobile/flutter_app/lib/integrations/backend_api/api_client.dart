import 'dart:convert';

import 'package:http/http.dart' as http;

import 'dto/google_auth_url_response_dto.dart';
import 'dto/provider_status_dto.dart';
import 'dto/providers_response_dto.dart';
import 'dto/today_events_response_dto.dart';

class BackendApiClient {
  BackendApiClient({required this.baseUrl, http.Client? httpClient})
    : _httpClient = httpClient ?? http.Client();

  final String baseUrl;
  final http.Client _httpClient;

  Uri _buildUri(String path, Map<String, String> query) {
    final normalized = baseUrl.endsWith('/')
        ? baseUrl.substring(0, baseUrl.length - 1)
        : baseUrl;
    return Uri.parse('$normalized$path').replace(queryParameters: query);
  }

  Future<TodayEventsResponseDto> fetchTodayEvents({
    String provider = 'google',
    int maxResults = 20,
    DateTime? date,
  }) async {
    final query = <String, String>{
      'provider': provider,
      'max_results': '$maxResults',
    };
    if (date != null) {
      final yyyy = date.year.toString().padLeft(4, '0');
      final mm = date.month.toString().padLeft(2, '0');
      final dd = date.day.toString().padLeft(2, '0');
      query['date'] = '$yyyy-$mm-$dd';
    }

    final uri = _buildUri('/api/events/today', query);
    final decoded = await _getJsonObject(uri);
    return TodayEventsResponseDto.fromJson(decoded);
  }

  Future<ProvidersResponseDto> fetchProviders() async {
    final uri = _buildUri('/api/providers', const <String, String>{});
    final decoded = await _getJsonObject(uri);
    return ProvidersResponseDto.fromJson(decoded);
  }

  Future<ProviderStatusDto> fetchProviderStatus({
    required String provider,
  }) async {
    final uri = _buildUri('/api/providers/status', <String, String>{
      'provider': provider,
    });
    final decoded = await _getJsonObject(uri);
    return ProviderStatusDto.fromJson(decoded);
  }

  Future<GoogleAuthUrlResponseDto> fetchGoogleAuthUrl() async {
    final uri = _buildUri(
      '/api/providers/google/auth-url',
      const <String, String>{},
    );
    final decoded = await _postJsonObject(uri);
    return GoogleAuthUrlResponseDto.fromJson(decoded);
  }

  Future<Map<String, dynamic>> _getJsonObject(Uri uri) async {
    final response = await _httpClient
        .get(uri)
        .timeout(const Duration(seconds: 8));

    final status = response.statusCode;
    final body = response.body;
    if (status < 200 || status >= 300) {
      throw BackendApiException(
        statusCode: status,
        message: _extractErrorMessage(body),
      );
    }

    final decoded = jsonDecode(body);
    if (decoded is! Map<String, dynamic>) {
      throw FormatException('Unexpected response format from $uri');
    }
    return decoded;
  }

  Future<Map<String, dynamic>> _postJsonObject(Uri uri) async {
    final response = await _httpClient
        .post(uri)
        .timeout(const Duration(seconds: 8));

    final status = response.statusCode;
    final body = response.body;
    if (status < 200 || status >= 300) {
      throw BackendApiException(
        statusCode: status,
        message: _extractErrorMessage(body),
      );
    }

    final decoded = jsonDecode(body);
    if (decoded is! Map<String, dynamic>) {
      throw FormatException('Unexpected response format from $uri');
    }
    return decoded;
  }

  String _extractErrorMessage(String body) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map<String, dynamic> && decoded['detail'] is String) {
        return decoded['detail'] as String;
      }
    } catch (_) {
      // Fall through to generic text.
    }
    return 'Backend request failed.';
  }

  void dispose() {
    _httpClient.close();
  }
}

class BackendApiException implements Exception {
  const BackendApiException({required this.statusCode, required this.message});

  final int statusCode;
  final String message;

  @override
  String toString() {
    return 'BackendApiException($statusCode): $message';
  }
}
