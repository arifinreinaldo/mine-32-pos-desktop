import 'package:drift/drift.dart';

import '../sync/change_log_writer.dart';
import '../sync/change_record.dart';
import '../sync/hlc_service.dart';
import '../time/clock.dart';
import '../time/hlc.dart';
import 'app_database.dart';

/// Base class for repositories of **syncable** entities. Guarantees the one
/// invariant the sync engine relies on: every mutation stamps a fresh HLC,
/// writes the row, and appends the matching outbox entry — all atomically.
abstract class SyncRepository {
  final AppDatabase db;
  final ChangeLogWriter changeLog;
  final HlcService hlcService;
  final Clock clock;

  SyncRepository({
    required this.db,
    required this.changeLog,
    required this.hlcService,
    required this.clock,
  });

  /// Stamp, persist, and record a syncable row atomically. [build] receives the
  /// freshly minted HLC and current time and must return the fully-populated row
  /// (with `updatedHlc`/`updatedAt` set to those values). Use [op] = delete and
  /// set the row's `deletedAt` to tombstone.
  Future<D> writeSyncable<D extends DataClass>({
    required String entityTable,
    required TableInfo<Table, D> table,
    required String rowId,
    required D Function(Hlc hlc, int nowMillis) build,
    ChangeOp op = ChangeOp.upsert,
  }) {
    return db.transaction(() async {
      final hlc = await hlcService.tick();
      final now = clock.nowMillis();
      final row = build(hlc, now);
      // Drift data classes implement Insertable<D> at runtime; the generic
      // bound `DataClass` doesn't express that statically, hence the cast.
      await db.into(table).insertOnConflictUpdate(row as Insertable<D>);
      await changeLog.record(
        entityTable: entityTable,
        rowId: rowId,
        op: op,
        payload: row.toJson(),
        hlc: hlc,
        nowMillis: now,
      );
      return row;
    });
  }

  /// Reads the original `created_at` of an existing row (any syncable table),
  /// so updates preserve creation time. Returns null if the row is absent.
  Future<int?> existingCreatedAt(
    TableInfo<Table, dynamic> table,
    String id,
  ) async {
    final idCol = table.columnsByName['id']! as GeneratedColumn<String>;
    final createdCol =
        table.columnsByName['created_at']! as GeneratedColumn<int>;
    final result =
        await (db.selectOnly(table)
              ..addColumns([createdCol])
              ..where(idCol.equals(id)))
            .getSingleOrNull();
    return result?.read(createdCol);
  }
}
