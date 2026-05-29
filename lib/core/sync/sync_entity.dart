import 'package:drift/drift.dart';

import '../database/app_database.dart';
import '../time/hlc.dart';
import 'change_record.dart';

enum SyncKind {
  /// Mutable master data — conflicts resolved last-write-wins by HLC.
  master,

  /// Append-only immutable events — merged by set union (insert-if-absent),
  /// which is conflict-free. Quantities/balances are projected from these.
  event,
}

/// Describes how to merge one syncable table during import. Features register
/// one per syncable table into the [SyncRegistry].
///
/// Generic over the Drift data class [D] so [apply] stays type-safe even when
/// the entity is stored in the registry as a raw `SyncEntity`.
class SyncEntity<D extends DataClass> {
  /// Logical name used in `change_log.entityTable` and bundle payloads.
  final String name;
  final SyncKind kind;
  final TableInfo<Table, D> Function(AppDatabase db) tableOf;
  final D Function(Map<String, dynamic> json) fromJson;

  const SyncEntity({
    required this.name,
    required this.kind,
    required this.tableOf,
    required this.fromJson,
  });

  /// Merge a single incoming [change] into [db] per this entity's [kind].
  Future<void> apply(AppDatabase db, ChangeRecord change) async {
    final table = tableOf(db);
    // Drift data classes implement Insertable<D> at runtime; the generic bound
    // `DataClass` doesn't express that statically, hence the cast.
    final row = fromJson(change.payload) as Insertable<D>;
    switch (kind) {
      case SyncKind.master:
        final existing = await _existingHlc(db, table, change.rowId);
        if (existing == null || change.hlc > existing) {
          await db.into(table).insertOnConflictUpdate(row);
        }
      case SyncKind.event:
        await db.into(table).insert(row, mode: InsertMode.insertOrIgnore);
    }
  }

  Future<Hlc?> _existingHlc(
    AppDatabase db,
    TableInfo<Table, D> table,
    String rowId,
  ) async {
    final idCol = table.columnsByName['id']! as GeneratedColumn<String>;
    final hlcCol =
        table.columnsByName['updated_hlc']! as GeneratedColumn<String>;
    final query = db.selectOnly(table)
      ..addColumns([hlcCol])
      ..where(idCol.equals(rowId));
    final result = await query.getSingleOrNull();
    final packed = result?.read(hlcCol);
    return packed == null ? null : Hlc.unpack(packed);
  }
}

/// All syncable entities, populated at startup by each feature's wiring.
class SyncRegistry {
  final Map<String, SyncEntity> _byName = {};

  void register(SyncEntity entity) => _byName[entity.name] = entity;

  SyncEntity? operator [](String name) => _byName[name];

  Iterable<SyncEntity> get all => _byName.values;

  bool get isEmpty => _byName.isEmpty;
}
