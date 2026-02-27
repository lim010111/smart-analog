import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_app/integrations/backend_api/dto/json_contract.dart';

void main() {
  group('json contract helper', () {
    test('requireNonEmptyString rejects empty values', () {
      expect(
        () => requireNonEmptyString(<String, dynamic>{'key': ''}, 'key'),
        throwsA(isA<FormatException>()),
      );
    });

    test('optionalString returns null for missing key', () {
      final value = optionalString(<String, dynamic>{}, 'missing');
      expect(value, isNull);
    });

    test('requireObjectList rejects non-object members', () {
      expect(
        () => requireObjectList(<String, dynamic>{
          'items': <dynamic>[1, 2, 3],
        }, 'items'),
        throwsA(isA<FormatException>()),
      );
    });

    test('requireIsoDateTime parses ISO value', () {
      final parsed = requireIsoDateTime(<String, dynamic>{
        'ts': '2026-02-27T10:00:00+09:00',
      }, 'ts');
      expect(parsed.toUtc().toIso8601String(), '2026-02-27T01:00:00.000Z');
    });
  });
}
