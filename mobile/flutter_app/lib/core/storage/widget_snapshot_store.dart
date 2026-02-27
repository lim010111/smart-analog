import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../../features/calendar/domain/models/widget_snapshot.dart';

const int widgetReadSchemaVersion = 1;
const String widgetReadSnapshotFileName = 'widget_snapshot_read_v1.json';

typedef SnapshotDirectoryResolver = Future<Directory> Function();

Map<String, dynamic> buildWidgetReadPayload(WidgetSnapshot snapshot) {
  return <String, dynamic>{
    'schema_version': widgetReadSchemaVersion,
    'generated_at': snapshot.generatedAt.toIso8601String(),
    'snapshot': snapshot.toJson(),
  };
}

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
  FileWidgetSnapshotStore({
    this.fileName = 'widget_snapshot.json',
    this.widgetReadFileName = widgetReadSnapshotFileName,
    SnapshotDirectoryResolver? snapshotDirectoryResolver,
  }) : _snapshotDirectoryResolver =
           snapshotDirectoryResolver ?? getApplicationSupportDirectory;

  final SnapshotDirectoryResolver _snapshotDirectoryResolver;

  final String fileName;
  final String widgetReadFileName;

  Future<File> _snapshotFile() async {
    final baseDirectory = await _snapshotDirectoryResolver();
    return File('${baseDirectory.path}/$fileName');
  }

  Future<File> _widgetReadFile() async {
    final baseDirectory = await _snapshotDirectoryResolver();
    return File('${baseDirectory.path}/$widgetReadFileName');
  }

  Future<void> _writeJsonFile(File file, Map<String, dynamic> payload) async {
    final tempFile = File('${file.path}.tmp');
    final encoded = jsonEncode(payload);
    await file.parent.create(recursive: true);
    await tempFile.writeAsString(encoded, flush: true);
    if (await file.exists()) {
      await file.delete();
    }
    await tempFile.rename(file.path);
  }

  @override
  Future<void> save(WidgetSnapshot snapshot) async {
    final file = await _snapshotFile();
    final widgetReadFile = await _widgetReadFile();
    await _writeJsonFile(file, snapshot.toJson());
    await _writeJsonFile(widgetReadFile, buildWidgetReadPayload(snapshot));
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
    final widgetReadFile = await _widgetReadFile();
    final exists = await file.exists();
    if (exists) {
      await file.delete();
    }
    final widgetReadExists = await widgetReadFile.exists();
    if (widgetReadExists) {
      await widgetReadFile.delete();
    }
  }
}
