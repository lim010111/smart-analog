import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../../features/calendar/domain/models/widget_snapshot.dart';

abstract interface class WidgetSnapshotStore {
  Future<void> save(WidgetSnapshot snapshot);

  Future<WidgetSnapshot?> load();

  Future<void> clear();
}

class InMemoryWidgetSnapshotStore implements WidgetSnapshotStore {
  WidgetSnapshot? _snapshot;

  @override
  Future<void> save(WidgetSnapshot snapshot) async {
    _snapshot = snapshot;
  }

  @override
  Future<WidgetSnapshot?> load() async {
    return _snapshot;
  }

  @override
  Future<void> clear() async {
    _snapshot = null;
  }
}

class FileWidgetSnapshotStore implements WidgetSnapshotStore {
  FileWidgetSnapshotStore({this.fileName = 'widget_snapshot.json'});

  final String fileName;

  Future<File> _snapshotFile() async {
    final baseDirectory = await getApplicationSupportDirectory();
    return File('${baseDirectory.path}/$fileName');
  }

  @override
  Future<void> save(WidgetSnapshot snapshot) async {
    final file = await _snapshotFile();
    final payload = jsonEncode(snapshot.toJson());
    await file.writeAsString(payload, flush: true);
  }

  @override
  Future<WidgetSnapshot?> load() async {
    final file = await _snapshotFile();
    final exists = await file.exists();
    if (!exists) {
      return null;
    }

    final raw = await file.readAsString();
    if (raw.trim().isEmpty) {
      return null;
    }

    final decoded = jsonDecode(raw);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException(
        'widget_snapshot.json must contain a JSON object.',
      );
    }

    return WidgetSnapshot.fromJson(decoded);
  }

  @override
  Future<void> clear() async {
    final file = await _snapshotFile();
    final exists = await file.exists();
    if (exists) {
      await file.delete();
    }
  }
}
