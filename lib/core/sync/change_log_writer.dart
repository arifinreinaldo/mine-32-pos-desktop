import 'dart:convert';

import 'package:uuid/uuid.dart';

import '../database/app_database.dart';
import '../time/hlc.dart';
import 'change_record.dart';

/// Appends entries to the outbox (`change_log`). MUST be invoked inside the same
/// transaction as the corresponding row write so a row and its change record
/// commit atomically (see `SyncRepository`).
class ChangeLogWriter {
  final AppDatabase _db;
  final String deviceId;
  final Uuid _uuid;

  ChangeLogWriter(this._db, this.deviceId, {Uuid? uuid})
    : _uuid = uuid ?? const Uuid();

  Future<void> record({
    required String entityTable,
    required String rowId,
    required ChangeOp op,
    required Map<String, dynamic> payload,
    required Hlc hlc,
    required int nowMillis,
  }) async {
    await _db
        .into(_db.changeLog)
        .insert(
          ChangeLogCompanion.insert(
            id: _uuid.v7(),
            entityTable: entityTable,
            rowId: rowId,
            operation: op.name,
            payload: jsonEncode(payload),
            hlc: hlc.pack(),
            deviceId: deviceId,
            createdAt: nowMillis,
          ),
        );
  }
}
