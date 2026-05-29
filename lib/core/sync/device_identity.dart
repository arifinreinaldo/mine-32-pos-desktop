import 'package:uuid/uuid.dart';

import '../database/app_database.dart';

/// Stable per-installation identity, persisted in `sync_meta`. The device id is
/// the node id of this device's HLC and the name of its outbox folder.
class DeviceIdentity {
  static const _idKey = 'device.id';
  static const _nameKey = 'device.name';

  final AppDatabase _db;
  final Uuid _uuid;

  DeviceIdentity(this._db, {Uuid? uuid}) : _uuid = uuid ?? const Uuid();

  Future<String> ensureId() async {
    final existing = await _get(_idKey);
    if (existing != null) return existing;
    final id = _uuid.v4();
    await _set(_idKey, id);
    return id;
  }

  Future<String> name() async => await _get(_nameKey) ?? 'This PC';

  Future<void> setName(String value) => _set(_nameKey, value);

  Future<String?> _get(String key) async {
    final row = await (_db.select(
      _db.syncMeta,
    )..where((t) => t.key.equals(key))).getSingleOrNull();
    return row?.value;
  }

  Future<void> _set(String key, String value) async {
    await _db
        .into(_db.syncMeta)
        .insertOnConflictUpdate(
          SyncMetaCompanion.insert(key: key, value: value),
        );
  }
}
