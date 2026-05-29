import 'package:drift/drift.dart';

import '../syncable_table.dart';

/// Known devices/installations in the sync mesh. Master data (LWW). The row
/// whose [id] equals this install's device id represents "us".
class Devices extends Table with SyncableTable {
  TextColumn get name => text()();
  TextColumn get platform => text().nullable()();

  /// Latest HLC this device is known to have produced.
  TextColumn get lastSeenHlc => text().nullable()();
}

/// The outbox / operation log. Every repository mutation appends one row here in
/// the same transaction as the data write. This log *is* the sync payload; it is
/// not itself a synced table.
class ChangeLog extends Table {
  /// Change id (UUID) — also the idempotency key on the receiving side.
  TextColumn get id => text()();

  /// Name of the entity/table this change targets (e.g. 'products').
  /// (Not named `tableName` — that is a reserved Drift override.)
  TextColumn get entityTable => text()();
  TextColumn get rowId => text()();

  /// 'upsert' | 'delete'.
  TextColumn get operation => text()();

  /// JSON snapshot of the row at write time.
  TextColumn get payload => text()();

  /// Packed HLC stamped on this change.
  TextColumn get hlc => text()();
  TextColumn get deviceId => text()();

  /// Whether this change has already been written into an export bundle.
  BoolColumn get exported => boolean().withDefault(const Constant(false))();
  IntColumn get createdAt => integer()();

  @override
  Set<Column> get primaryKey => {id};
}

/// Idempotency ledger of change ids already applied (local or remote), so
/// re-importing a bundle is a no-op.
class AppliedChanges extends Table {
  TextColumn get changeId => text()();
  TextColumn get sourceDeviceId => text()();
  IntColumn get appliedAt => integer()();

  @override
  Set<Column> get primaryKey => {changeId};
}

/// Key/value store for sync cursors and misc local metadata
/// (e.g. last export HLC, per-peer import cursor, transport config).
class SyncMeta extends Table {
  TextColumn get key => text()();
  TextColumn get value => text()();

  @override
  Set<Column> get primaryKey => {key};
}
