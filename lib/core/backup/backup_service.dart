import 'dart:convert';

import '../database/app_database.dart';
import '../sync/change_record.dart';
import '../sync/sync_entity.dart';
import '../time/hlc.dart';

/// Result of restoring a backup.
class BackupResult {
  final int tables;
  final int rows;
  const BackupResult({required this.tables, required this.rows});
}

/// Full data backup & restore for the offline-first database.
///
/// A backup is a JSON snapshot of **every registered syncable table's** current
/// rows (tombstones included), independent of which device produced them — so it
/// captures data that arrived via sync as well as locally-entered data. Restore
/// merges the snapshot back in using each entity's normal conflict rules
/// (master = HLC last-write-wins, event = set union), making it safe to restore
/// into a populated database and idempotent if run twice.
class BackupService {
  final AppDatabase db;
  final SyncRegistry registry;
  final List<Future<void> Function()> reprojectors;

  /// Bumped if the snapshot envelope shape changes.
  static const int formatVersion = 1;

  BackupService({
    required this.db,
    required this.registry,
    this.reprojectors = const [],
  });

  /// Build the snapshot map (every syncable table → list of row JSON).
  Future<Map<String, dynamic>> exportSnapshot() async {
    final tables = <String, dynamic>{};
    for (final entity in registry.all) {
      final rows = await db.select(entity.tableOf(db)).get();
      tables[entity.name] = [for (final r in rows) r.toJson()];
    }
    return {
      'format': formatVersion,
      'schema': db.schemaVersion,
      'exportedAt': DateTime.now().toUtc().toIso8601String(),
      'tables': tables,
    };
  }

  /// The snapshot as pretty-printed UTF-8 JSON bytes, ready to write to a file.
  Future<List<int>> exportBytes() async {
    return utf8.encode(
      const JsonEncoder.withIndent('  ').convert(await exportSnapshot()),
    );
  }

  /// Merge a decoded snapshot back into the database.
  Future<BackupResult> importSnapshot(Map<String, dynamic> snapshot) async {
    final tables = (snapshot['tables'] as Map).cast<String, dynamic>();
    var tableCount = 0;
    var rowCount = 0;
    await db.transaction(() async {
      for (final entry in tables.entries) {
        final entity = registry[entry.key];
        if (entity == null) continue; // unknown table (e.g. newer backup)
        tableCount++;
        for (final raw in entry.value as List) {
          final json = (raw as Map).cast<String, dynamic>();
          // Drift's toJson() uses camelCase keys.
          final hlcPacked = json['updatedHlc'] as String?;
          final id = json['id'] as String?;
          if (hlcPacked == null || id == null) continue;
          await entity.apply(
            db,
            ChangeRecord(
              id: 'backup',
              entityTable: entity.name,
              rowId: id,
              op: ChangeOp.upsert,
              payload: json,
              hlc: Hlc.unpack(hlcPacked),
              deviceId: 'backup',
              createdAt: 0,
            ),
          );
          rowCount++;
        }
      }
    });
    for (final reproject in reprojectors) {
      await reproject();
    }
    return BackupResult(tables: tableCount, rows: rowCount);
  }

  /// Decode and restore from backup file bytes. Throws [FormatException] if the
  /// bytes are not a recognisable backup.
  Future<BackupResult> importBytes(List<int> bytes) async {
    final decoded = jsonDecode(utf8.decode(bytes));
    if (decoded is! Map || !decoded.containsKey('tables')) {
      throw const FormatException('Not a valid Mine32 backup file');
    }
    return importSnapshot(decoded.cast<String, dynamic>());
  }
}
