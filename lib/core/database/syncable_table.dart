import 'package:drift/drift.dart';

/// Columns every **syncable** entity carries so the serverless sync engine can
/// merge it deterministically (see `docs/SYNC.md`).
///
/// Concrete tables: `class Products extends Table with SyncableTable { ... }`.
mixin SyncableTable on Table {
  /// UUID v7 string, generated client-side (never an autoincrement int).
  TextColumn get id => text()();

  /// Epoch millis (UTC) the row was first created.
  IntColumn get createdAt => integer()();

  /// Epoch millis (UTC) of the most recent local or merged write.
  IntColumn get updatedAt => integer()();

  /// Tombstone: epoch millis when soft-deleted, or null while live.
  IntColumn get deletedAt => integer().nullable()();

  /// Packed HLC of the last write — drives last-write-wins resolution.
  TextColumn get updatedHlc => text()();

  @override
  Set<Column> get primaryKey => {id};
}
