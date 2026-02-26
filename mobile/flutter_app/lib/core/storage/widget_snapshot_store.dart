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
