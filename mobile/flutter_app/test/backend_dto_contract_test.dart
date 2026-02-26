import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_app/integrations/backend_api/dto/google_auth_url_response_dto.dart';
import 'package:flutter_app/integrations/backend_api/dto/providers_response_dto.dart';
import 'package:flutter_app/integrations/backend_api/dto/web_event_dto.dart';

void main() {
  group('backend dto contracts', () {
    test('parses providers response with required fields', () {
      final dto = ProvidersResponseDto.fromJson(<String, dynamic>{
        'default_provider': 'google',
        'providers': <String>['google', 'apple'],
      });

      expect(dto.defaultProvider, 'google');
      expect(dto.providers, <String>['google', 'apple']);
    });

    test('throws on missing required providers fields', () {
      expect(
        () => ProvidersResponseDto.fromJson(<String, dynamic>{
          'providers': <String>['google'],
        }),
        throwsA(isA<FormatException>()),
      );
    });

    test('parses web event dto with ISO datetime fields', () {
      final dto = WebEventDto.fromJson(<String, dynamic>{
        'id': 'evt-1',
        'summary': 'Standup',
        'description': '',
        'start_time': '2026-02-27T08:30:00+09:00',
        'end_time': '2026-02-27T09:00:00+09:00',
        'all_day': false,
        'color_hex': '#3A86FF',
        'provider_color_id': null,
      });

      expect(dto.id, 'evt-1');
      expect(
        dto.startTime.toUtc().toIso8601String(),
        '2026-02-26T23:30:00.000Z',
      );
      expect(dto.endTime.isAfter(dto.startTime), true);
    });

    test('throws on invalid web event datetime contract', () {
      expect(
        () => WebEventDto.fromJson(<String, dynamic>{
          'id': 'evt-2',
          'summary': 'Broken',
          'description': '',
          'end_time': '2026-02-27T09:00:00+09:00',
          'all_day': false,
          'color_hex': '#3A86FF',
          'provider_color_id': null,
        }),
        throwsA(isA<FormatException>()),
      );
    });

    test('throws on missing google auth response fields', () {
      expect(
        () => GoogleAuthUrlResponseDto.fromJson(<String, dynamic>{
          'provider': 'google',
          'auth_url': 'https://accounts.google.com/o/oauth2/v2/auth',
          'state': 'abc',
          'redirect_uri': 'https://example.com/callback',
        }),
        throwsA(isA<FormatException>()),
      );
    });
  });
}
