import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_app/core/storage/widget_snapshot_store.dart';
import 'package:flutter_app/features/calendar/application/widget_snapshot_builder.dart';
import 'package:flutter_app/features/calendar/domain/models/calendar_event.dart';

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('cw_widget_store_test_');
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  test('save writes main snapshot and widget read payload', () async {
    final store = FileWidgetSnapshotStore(
      snapshotDirectoryResolver: () async => tempDir,
    );
    final now = DateTime(2026, 3, 2, 10, 30, 0);
    final snapshot = const WidgetSnapshotBuilder().build(
      now: now,
      timezone: 'Asia/Seoul',
      events: <CalendarEvent>[
        CalendarEvent(
          id: 'evt-1',
          title: 'Focus time',
          description: '',
          startTime: DateTime(2026, 3, 2, 11, 0, 0),
          endTime: DateTime(2026, 3, 2, 11, 30, 0),
          allDay: false,
          colorHex: '#3A86FF',
          provider: 'google',
        ),
      ],
    );

    await store.save(snapshot);

    final mainFile = File('${tempDir.path}/widget_snapshot.json');
    final widgetReadFile = File('${tempDir.path}/$widgetReadSnapshotFileName');
    expect(await mainFile.exists(), isTrue);
    expect(await widgetReadFile.exists(), isTrue);

    final readPayload =
        jsonDecode(await widgetReadFile.readAsString()) as Map<String, dynamic>;
    expect(readPayload['schema_version'], widgetReadSchemaVersion);
    expect(readPayload['snapshot'], isA<Map<String, dynamic>>());

    final loaded = await store.load();
    expect(loaded, isNotNull);
    expect(loaded!.events.length, 1);
    expect(loaded.segments.length, 1);
  });

  test('clear removes main snapshot and widget read payload', () async {
    final store = FileWidgetSnapshotStore(
      snapshotDirectoryResolver: () async => tempDir,
    );
    final snapshot = const WidgetSnapshotBuilder().build(
      now: DateTime(2026, 3, 2, 9, 0, 0),
      timezone: 'Asia/Seoul',
      events: const <CalendarEvent>[],
    );

    await store.save(snapshot);
    await store.clear();

    expect(
      await File('${tempDir.path}/widget_snapshot.json').exists(),
      isFalse,
    );
    expect(
      await File('${tempDir.path}/$widgetReadSnapshotFileName').exists(),
      isFalse,
    );
  });
}
