import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_app/integrations/backend_api/dto/briefing_response_dto.dart';
import 'package:flutter_app/integrations/backend_api/dto/colors_response_dto.dart';
import 'package:flutter_app/integrations/backend_api/dto/create_event_response_dto.dart';
import 'package:flutter_app/integrations/backend_api/dto/natural_input_response_dto.dart';
import 'package:flutter_app/integrations/backend_api/dto/provider_auth_response_dto.dart';
import 'package:flutter_app/integrations/backend_api/dto/settings_response_dto.dart';

void main() {
  group('mvp parity dto contracts', () {
    test('parses settings response', () {
      final dto = SettingsResponseDto.fromJson(<String, dynamic>{
        'theme': 'dark',
        'event_opacity': 150,
        'clock_opacity': 100,
        'briefing_enabled': true,
        'briefing_tts_enabled': false,
        'widget_pinned': true,
      });

      expect(dto.theme, 'dark');
      expect(dto.eventOpacity, 150);
      expect(dto.widgetPinned, isTrue);
    });

    test('parses provider auth/logout responses', () {
      final auth = ProviderAuthResponseDto.fromJson(<String, dynamic>{
        'provider': 'apple',
        'authenticated': true,
      });
      final logout = ProviderLogoutResponseDto.fromJson(<String, dynamic>{
        'provider': 'google',
        'logged_out': true,
      });

      expect(auth.authenticated, isTrue);
      expect(logout.loggedOut, isTrue);
    });

    test('parses create-event response', () {
      final dto = CreateEventResponseDto.fromJson(<String, dynamic>{
        'provider': 'google',
        'event': <String, dynamic>{
          'id': 'evt-1',
          'summary': 'Meeting',
          'description': '',
          'start_time': '2026-02-27T10:00:00+09:00',
          'end_time': '2026-02-27T11:00:00+09:00',
          'all_day': false,
          'color_hex': '#3A86FF',
          'provider_color_id': null,
        },
      });

      expect(dto.provider, 'google');
      expect(dto.event.id, 'evt-1');
    });

    test('parses natural parse/create responses', () {
      final parse = NaturalParseResponseDto.fromJson(<String, dynamic>{
        'provider': 'google',
        'ready': true,
        'result': <String, dynamic>{
          'intent': 'create',
          'title': 'Lunch',
          'start_time': '2026-02-27T12:00:00+09:00',
          'end_time': '2026-02-27T13:00:00+09:00',
          'all_day': false,
          'confidence': 0.9,
          'note': null,
        },
      });

      final create = NaturalCreateResponseDto.fromJson(<String, dynamic>{
        'provider': 'google',
        'parsed': <String, dynamic>{
          'intent': 'create',
          'title': 'Lunch',
          'start_time': '2026-02-27T12:00:00+09:00',
          'end_time': '2026-02-27T13:00:00+09:00',
          'all_day': false,
          'confidence': 0.9,
          'note': null,
        },
        'created': null,
      });

      expect(parse.result, isNotNull);
      expect(create.parsed.intent, 'create');
    });

    test('parses briefing and color endpoints', () {
      final briefing = BriefingResponseDto.fromJson(<String, dynamic>{
        'provider': 'google',
        'generated_at': '2026-02-27T10:00:00+09:00',
        'briefing': '오늘 일정 3건입니다.',
        'event_count': 3,
        'disabled': false,
      });

      final schema = ColorSchemaResponseDto.fromJson(<String, dynamic>{
        'provider': 'google',
        'rules': <Map<String, dynamic>>[
          <String, dynamic>{'color_hex': '#3A86FF', 'label': 'Focus'},
        ],
      });

      final apply = ApplyColorsResponseDto.fromJson(<String, dynamic>{
        'provider': 'google',
        'processed': 10,
        'updated': 4,
        'processed_today': 3,
        'updated_today': 2,
        'background_started': true,
        'background_queued': false,
      });

      expect(briefing.eventCount, 3);
      expect(schema.rules.length, 1);
      expect(apply.updated, 4);
    });

    test('parses apply-status timestamps from numeric payload', () {
      final status = ApplyColorsStatusResponseDto.fromJson(<String, dynamic>{
        'provider': 'google',
        'running': true,
        'queued': false,
        'last_started_at': 1731570000.5,
        'last_finished_at': 1731570100,
        'last_processed': 22,
        'last_updated': 11,
        'last_error': '',
      });

      expect(status.lastStartedAt, '1731570000.5');
      expect(status.lastFinishedAt, '1731570100');
      expect(status.running, isTrue);
    });

    test('throws on malformed settings payload', () {
      expect(
        () => SettingsResponseDto.fromJson(<String, dynamic>{'theme': 'dark'}),
        throwsA(isA<FormatException>()),
      );
    });
  });
}
