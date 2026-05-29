import '../database/app_database.dart';
import '../time/clock.dart';
import '../time/hlc.dart';

/// Owns this device's Hybrid Logical Clock: produces monotonic HLCs for local
/// writes ([tick]) and merges remote HLCs on import ([observe]), persisting the
/// latest value so ordering survives restarts.
class HlcService {
  static const String _metaKey = 'hlc.last';

  final AppDatabase _db;
  final Clock _clock;
  final String deviceId;

  Hlc _current;

  HlcService(this._db, this._clock, this.deviceId)
    : _current = Hlc.zero(deviceId);

  Hlc get current => _current;

  /// Load the persisted clock. Call once at startup before any writes.
  Future<void> load() async {
    final row = await (_db.select(
      _db.syncMeta,
    )..where((t) => t.key.equals(_metaKey))).getSingleOrNull();
    if (row != null) {
      final stored = Hlc.unpack(row.value);
      // Keep our own nodeId; adopt the stored physical/counter position.
      _current = Hlc(
        millis: stored.millis,
        counter: stored.counter,
        nodeId: deviceId,
      );
    }
  }

  /// Next HLC for a new local event.
  Future<Hlc> tick() async {
    _current = _current.increment(_clock.nowMillis());
    await _persist();
    return _current;
  }

  /// Merge an observed remote HLC into the local clock (call on import).
  Future<Hlc> observe(Hlc remote) async {
    _current = _current.receive(remote, _clock.nowMillis());
    await _persist();
    return _current;
  }

  Future<void> _persist() async {
    await _db
        .into(_db.syncMeta)
        .insertOnConflictUpdate(
          SyncMetaCompanion.insert(key: _metaKey, value: _current.pack()),
        );
  }
}
