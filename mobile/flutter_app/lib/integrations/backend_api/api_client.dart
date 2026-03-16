import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import 'dto/apple_credentials_response_dto.dart';
import 'dto/briefing_response_dto.dart';
import 'dto/color_rule_dto.dart';
import 'dto/colors_response_dto.dart';
import 'dto/create_event_response_dto.dart';
import 'dto/google_auth_url_response_dto.dart';
import 'dto/natural_input_response_dto.dart';
import 'dto/provider_auth_response_dto.dart';
import 'dto/provider_status_dto.dart';
import 'dto/providers_response_dto.dart';
import 'dto/settings_response_dto.dart';
import 'dto/today_events_response_dto.dart';

class BackendApiClient {
  BackendApiClient({required this.baseUrl, http.Client? httpClient})
    : _httpClient = httpClient ?? http.Client();

  final String baseUrl;
  final http.Client _httpClient;
  String? _preferredAndroidHost;

  static const Set<String> _androidLocalHosts = <String>{
    '10.0.2.2',
    '10.0.0.2',
    '127.0.0.1',
    'localhost',
  };

  Uri _buildUri(String path, Map<String, String> query) {
    final normalized = baseUrl.endsWith('/')
        ? baseUrl.substring(0, baseUrl.length - 1)
        : baseUrl;
    return Uri.parse('$normalized$path').replace(queryParameters: query);
  }

  List<Uri> _androidCandidateUris(Uri primary) {
    if (!Platform.isAndroid) {
      return <Uri>[primary];
    }

    final hosts = <String>[primary.host];
    if (primary.host == '10.0.2.2') {
      hosts.addAll(<String>['127.0.0.1', 'localhost']);
    } else if (primary.host == '10.0.0.2') {
      hosts.addAll(<String>['10.0.2.2', '127.0.0.1', 'localhost']);
    } else if (primary.host == '127.0.0.1') {
      hosts.addAll(<String>['localhost', '10.0.2.2']);
    } else if (primary.host == 'localhost') {
      hosts.addAll(<String>['127.0.0.1', '10.0.2.2']);
    }

    final uniqueHosts = <String>[];
    for (final host in hosts) {
      if (!uniqueHosts.contains(host)) {
        uniqueHosts.add(host);
      }
    }

    final candidates = uniqueHosts
        .map((host) => primary.replace(host: host))
        .toList();
    final preferred = _preferredAndroidHost;
    if (preferred == null) {
      return candidates;
    }

    final preferredIndex = candidates.indexWhere(
      (candidate) => candidate.host == preferred,
    );
    if (preferredIndex <= 0) {
      return candidates;
    }

    final preferredUri = candidates.removeAt(preferredIndex);
    return <Uri>[preferredUri, ...candidates];
  }

  Duration _requestTimeoutForCandidate({
    required Uri candidate,
    required int candidateIndex,
    required int candidateCount,
  }) {
    final path = candidate.path.toLowerCase();
    final isAiEndpoint =
        path.startsWith('/api/events/natural-input/') ||
        path.startsWith('/api/briefing/');
    if (isAiEndpoint) {
      if (Platform.isAndroid && _androidLocalHosts.contains(candidate.host)) {
        return const Duration(seconds: 25);
      }
      return const Duration(seconds: 40);
    }

    if (Platform.isAndroid && _androidLocalHosts.contains(candidate.host)) {
      return const Duration(seconds: 3);
    }
    if (Platform.isAndroid && candidateCount > 1 && candidateIndex == 0) {
      return const Duration(seconds: 4);
    }
    return const Duration(seconds: 8);
  }

  void _rememberSuccessfulAndroidHost(Uri candidate) {
    if (!Platform.isAndroid) {
      return;
    }
    if (_androidLocalHosts.contains(candidate.host)) {
      _preferredAndroidHost = candidate.host;
    }
  }

  bool _isNetworkException(Object error) {
    return error is SocketException ||
        error is HttpException ||
        error is TimeoutException ||
        error is http.ClientException;
  }

  Future<TodayEventsResponseDto> fetchTodayEvents({
    String provider = 'google',
    int maxResults = 20,
    DateTime? date,
    bool applyColors = false,
  }) async {
    final effectiveDate = date ?? DateTime.now();
    final query = <String, String>{
      'provider': provider,
      'max_results': '$maxResults',
      'tz_offset_minutes': '${effectiveDate.timeZoneOffset.inMinutes}',
    };
    if (date != null) {
      final yyyy = effectiveDate.year.toString().padLeft(4, '0');
      final mm = effectiveDate.month.toString().padLeft(2, '0');
      final dd = effectiveDate.day.toString().padLeft(2, '0');
      query['date'] = '$yyyy-$mm-$dd';
    }
    query['apply_colors'] = applyColors ? 'true' : 'false';

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
    bool includeIdentity = false,
  }) async {
    final query = <String, String>{
      'provider': provider,
      if (includeIdentity) 'include_identity': 'true',
    };
    final uri = _buildUri('/api/providers/status', query);
    final decoded = await _getJsonObject(uri);
    return ProviderStatusDto.fromJson(decoded);
  }

  Future<GoogleAuthUrlResponseDto> fetchGoogleAuthUrl({
    String? mobileCallback,
  }) async {
    final query = <String, String>{};
    if (mobileCallback != null && mobileCallback.trim().isNotEmpty) {
      query['mobile_callback'] = mobileCallback.trim();
    }
    final uri = _buildUri('/api/providers/google/auth-url', query);
    final decoded = await _postJsonObject(uri);
    return GoogleAuthUrlResponseDto.fromJson(decoded);
  }

  Future<AppleCredentialsResponseDto> setAppleCredentials({
    required String appleId,
    required String appPassword,
  }) async {
    final uri = _buildUri(
      '/api/providers/apple/credentials',
      const <String, String>{},
    );
    final decoded = await _postJsonObject(
      uri,
      jsonBody: <String, dynamic>{
        'apple_id': appleId,
        'app_password': appPassword,
      },
    );
    return AppleCredentialsResponseDto.fromJson(decoded);
  }

  Future<ProviderAuthResponseDto> authenticateProvider({
    required String provider,
  }) async {
    final uri = _buildUri('/api/providers/authenticate', <String, String>{
      'provider': provider,
    });
    final decoded = await _postJsonObject(uri);
    return ProviderAuthResponseDto.fromJson(decoded);
  }

  Future<ProviderLogoutResponseDto> logoutProvider({
    required String provider,
  }) async {
    final uri = _buildUri('/api/providers/logout', <String, String>{
      'provider': provider,
    });
    final decoded = await _postJsonObject(uri);
    return ProviderLogoutResponseDto.fromJson(decoded);
  }

  Future<SettingsResponseDto> fetchSettings() async {
    final uri = _buildUri('/api/settings', const <String, String>{});
    final decoded = await _getJsonObject(uri);
    return SettingsResponseDto.fromJson(decoded);
  }

  Future<SettingsResponseDto> updateSettings({
    required String theme,
    required String widgetTheme,
    required int eventOpacity,
    required int clockOpacity,
    required bool briefingEnabled,
    required bool briefingTtsEnabled,
  }) async {
    final uri = _buildUri('/api/settings', const <String, String>{});
    final decoded = await _putJsonObject(
      uri,
      jsonBody: <String, dynamic>{
        'theme': theme,
        'widget_theme': widgetTheme,
        'event_opacity': eventOpacity,
        'clock_opacity': clockOpacity,
        'briefing_enabled': briefingEnabled,
        'briefing_tts_enabled': briefingTtsEnabled,
      },
    );
    return SettingsResponseDto.fromJson(decoded);
  }

  Future<CreateEventResponseDto> createEvent({
    required String provider,
    required String summary,
    required String startTime,
    required String endTime,
    required bool allDay,
  }) async {
    final uri = _buildUri('/api/events/create', <String, String>{
      'provider': provider,
    });
    final decoded = await _postJsonObject(
      uri,
      jsonBody: <String, dynamic>{
        'summary': summary,
        'start_time': startTime,
        'end_time': endTime,
        'all_day': allDay,
      },
    );
    return CreateEventResponseDto.fromJson(decoded);
  }

  Future<NaturalParseResponseDto> parseNaturalInput({
    required String provider,
    required String text,
  }) async {
    final uri = _buildUri('/api/events/natural-input/parse', <String, String>{
      'provider': provider,
    });
    final decoded = await _postJsonObject(
      uri,
      jsonBody: <String, dynamic>{'text': text},
    );
    return NaturalParseResponseDto.fromJson(decoded);
  }

  Future<NaturalCreateResponseDto> createEventFromNaturalInput({
    required String provider,
    required String text,
  }) async {
    final uri = _buildUri('/api/events/natural-input/create', <String, String>{
      'provider': provider,
    });
    final decoded = await _postJsonObject(
      uri,
      jsonBody: <String, dynamic>{'text': text},
    );
    return NaturalCreateResponseDto.fromJson(decoded);
  }

  Future<BriefingResponseDto> fetchTodayBriefing({
    required String provider,
    int maxResults = 20,
    bool force = true,
  }) async {
    final uri = _buildUri('/api/briefing/today', <String, String>{
      'provider': provider,
      'max_results': '$maxResults',
      'force': force ? 'true' : 'false',
    });
    final decoded = await _getJsonObject(uri);
    return BriefingResponseDto.fromJson(decoded);
  }

  Future<BriefingTtsBase64ResponseDto> generateBriefingTtsBase64({
    required String text,
    String responseFormat = 'wav',
    String? voice,
    String? model,
    String? instructions,
  }) async {
    final uri = _buildUri('/api/briefing/tts/base64', const <String, String>{});
    final decoded = await _postJsonObject(
      uri,
      jsonBody: <String, dynamic>{
        'text': text,
        'response_format': responseFormat,
        if (voice != null && voice.trim().isNotEmpty) 'voice': voice,
        if (model != null && model.trim().isNotEmpty) 'model': model,
        if (instructions != null && instructions.trim().isNotEmpty)
          'instructions': instructions,
      },
    );
    return BriefingTtsBase64ResponseDto.fromJson(decoded);
  }

  Future<BriefingTtsBinaryResponse> generateBriefingTtsBinary({
    required String text,
    String responseFormat = 'wav',
    String? voice,
    String? model,
    String? instructions,
  }) async {
    final uri = _buildUri('/api/briefing/tts', const <String, String>{});
    final response = await _postRaw(
      uri,
      jsonBody: <String, dynamic>{
        'text': text,
        'response_format': responseFormat,
        if (voice != null && voice.trim().isNotEmpty) 'voice': voice,
        if (model != null && model.trim().isNotEmpty) 'model': model,
        if (instructions != null && instructions.trim().isNotEmpty)
          'instructions': instructions,
      },
    );
    return BriefingTtsBinaryResponse(
      bytes: response.bodyBytes,
      mimeType: response.headers['content-type'] ?? 'application/octet-stream',
    );
  }

  Future<ColorPaletteResponseDto> fetchColorPalette({
    required String provider,
  }) async {
    final uri = _buildUri('/api/colors/palette', <String, String>{
      'provider': provider,
    });
    final decoded = await _getJsonObject(uri);
    return ColorPaletteResponseDto.fromJson(decoded);
  }

  Future<ColorSchemaResponseDto> fetchColorSchema({
    required String provider,
  }) async {
    final uri = _buildUri('/api/colors/schema', <String, String>{
      'provider': provider,
    });
    final decoded = await _getJsonObject(uri);
    return ColorSchemaResponseDto.fromJson(decoded);
  }

  Future<UpdateColorSchemaResponseDto> updateColorSchema({
    required String provider,
    required List<ColorRuleDto> rules,
  }) async {
    final uri = _buildUri('/api/colors/schema', <String, String>{
      'provider': provider,
    });
    final decoded = await _putJsonObject(
      uri,
      jsonBody: <String, dynamic>{
        'rules': rules.map((rule) => rule.toJson()).toList(),
      },
    );
    return UpdateColorSchemaResponseDto.fromJson(decoded);
  }

  Future<ApplyColorsResponseDto> applyColorsToAll({
    required String provider,
    int? maxResults,
    int pageSize = 250,
  }) async {
    final query = <String, String>{
      'provider': provider,
      'page_size': '$pageSize',
    };
    if (maxResults != null) {
      query['max_results'] = '$maxResults';
    }

    final uri = _buildUri('/api/colors/apply-all', query);
    final decoded = await _postJsonObject(uri);
    return ApplyColorsResponseDto.fromJson(decoded);
  }

  Future<ApplyColorsStatusResponseDto> fetchApplyColorsStatus({
    required String provider,
  }) async {
    final uri = _buildUri('/api/colors/apply-status', <String, String>{
      'provider': provider,
    });
    final decoded = await _getJsonObject(uri);
    return ApplyColorsStatusResponseDto.fromJson(decoded);
  }

  Future<Map<String, dynamic>> _getJsonObject(Uri uri) async {
    Object? lastNetworkError;
    final candidates = _androidCandidateUris(uri);
    for (var i = 0; i < candidates.length; i += 1) {
      final candidate = candidates[i];
      try {
        final response = await _httpClient
            .get(candidate)
            .timeout(
              _requestTimeoutForCandidate(
                candidate: candidate,
                candidateIndex: i,
                candidateCount: candidates.length,
              ),
            );

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
          throw FormatException('Unexpected response format from $candidate');
        }
        _rememberSuccessfulAndroidHost(candidate);
        return decoded;
      } on Exception catch (error) {
        if (_isNetworkException(error)) {
          lastNetworkError = error;
          continue;
        }
        rethrow;
      }
    }

    if (lastNetworkError != null) {
      throw lastNetworkError;
    }
    throw const HttpException('Backend request failed.');
  }

  Future<Map<String, dynamic>> _postJsonObject(
    Uri uri, {
    Map<String, dynamic>? jsonBody,
  }) async {
    final payload = jsonBody == null ? null : jsonEncode(jsonBody);
    Object? lastNetworkError;
    final candidates = _androidCandidateUris(uri);
    for (var i = 0; i < candidates.length; i += 1) {
      final candidate = candidates[i];
      try {
        final response = await _httpClient
            .post(
              candidate,
              headers: payload == null
                  ? const <String, String>{}
                  : const <String, String>{'Content-Type': 'application/json'},
              body: payload,
            )
            .timeout(
              _requestTimeoutForCandidate(
                candidate: candidate,
                candidateIndex: i,
                candidateCount: candidates.length,
              ),
            );

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
          throw FormatException('Unexpected response format from $candidate');
        }
        _rememberSuccessfulAndroidHost(candidate);
        return decoded;
      } on Exception catch (error) {
        if (_isNetworkException(error)) {
          lastNetworkError = error;
          continue;
        }
        rethrow;
      }
    }

    if (lastNetworkError != null) {
      throw lastNetworkError;
    }
    throw const HttpException('Backend request failed.');
  }

  Future<Map<String, dynamic>> _putJsonObject(
    Uri uri, {
    required Map<String, dynamic> jsonBody,
  }) async {
    final payload = jsonEncode(jsonBody);
    Object? lastNetworkError;
    final candidates = _androidCandidateUris(uri);
    for (var i = 0; i < candidates.length; i += 1) {
      final candidate = candidates[i];
      try {
        final response = await _httpClient
            .put(
              candidate,
              headers: const <String, String>{
                'Content-Type': 'application/json',
              },
              body: payload,
            )
            .timeout(
              _requestTimeoutForCandidate(
                candidate: candidate,
                candidateIndex: i,
                candidateCount: candidates.length,
              ),
            );

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
          throw FormatException('Unexpected response format from $candidate');
        }
        _rememberSuccessfulAndroidHost(candidate);
        return decoded;
      } on Exception catch (error) {
        if (_isNetworkException(error)) {
          lastNetworkError = error;
          continue;
        }
        rethrow;
      }
    }

    if (lastNetworkError != null) {
      throw lastNetworkError;
    }
    throw const HttpException('Backend request failed.');
  }

  Future<http.Response> _postRaw(
    Uri uri, {
    required Map<String, dynamic> jsonBody,
  }) async {
    final payload = jsonEncode(jsonBody);
    Object? lastNetworkError;
    final candidates = _androidCandidateUris(uri);
    for (var i = 0; i < candidates.length; i += 1) {
      final candidate = candidates[i];
      try {
        final response = await _httpClient
            .post(
              candidate,
              headers: const <String, String>{
                'Content-Type': 'application/json',
              },
              body: payload,
            )
            .timeout(
              _requestTimeoutForCandidate(
                candidate: candidate,
                candidateIndex: i,
                candidateCount: candidates.length,
              ),
            );

        if (response.statusCode < 200 || response.statusCode >= 300) {
          throw BackendApiException(
            statusCode: response.statusCode,
            message: _extractErrorMessage(response.body),
          );
        }
        _rememberSuccessfulAndroidHost(candidate);
        return response;
      } on Exception catch (error) {
        if (_isNetworkException(error)) {
          lastNetworkError = error;
          continue;
        }
        rethrow;
      }
    }

    if (lastNetworkError != null) {
      throw lastNetworkError;
    }
    throw const HttpException('Backend request failed.');
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

class BriefingTtsBinaryResponse {
  const BriefingTtsBinaryResponse({
    required this.bytes,
    required this.mimeType,
  });

  final Uint8List bytes;
  final String mimeType;
}
