import '../time/hlc.dart';

/// Whether a change creates/updates a row or tombstones it. Deletes are carried
/// as upserts with `deletedAt` set, so both ops apply via the same path; the op
/// is kept for clarity/auditing and future hard-delete support.
enum ChangeOp { upsert, delete }

/// A single replicated mutation. This is both an outbox entry and the unit
/// exchanged inside a [SyncBundle]. [payload] is the entity's Drift `toJson()`
/// snapshot (camelCase keys), reconstructable via the registered `fromJson`.
class ChangeRecord {
  final String id; // change id (UUID) — idempotency key
  final String entityTable;
  final String rowId;
  final ChangeOp op;
  final Map<String, dynamic> payload;
  final Hlc hlc;
  final String deviceId;
  final int createdAt;

  const ChangeRecord({
    required this.id,
    required this.entityTable,
    required this.rowId,
    required this.op,
    required this.payload,
    required this.hlc,
    required this.deviceId,
    required this.createdAt,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'entityTable': entityTable,
    'rowId': rowId,
    'op': op.name,
    'payload': payload,
    'hlc': hlc.pack(),
    'deviceId': deviceId,
    'createdAt': createdAt,
  };

  factory ChangeRecord.fromJson(Map<String, dynamic> j) => ChangeRecord(
    id: j['id'] as String,
    entityTable: j['entityTable'] as String,
    rowId: j['rowId'] as String,
    op: ChangeOp.values.byName(j['op'] as String),
    payload: (j['payload'] as Map).cast<String, dynamic>(),
    hlc: Hlc.unpack(j['hlc'] as String),
    deviceId: j['deviceId'] as String,
    createdAt: j['createdAt'] as int,
  );
}

/// A portable, immutable batch of changes from one device, exchanged through a
/// [SyncTransport]. Named by [toHlc] so peers can resume from a cursor.
class SyncBundle {
  static const int currentSchemaVersion = 1;

  final int schemaVersion;
  final String deviceId;
  final String fromHlc; // packed (exclusive lower bound, '' if from start)
  final String toHlc; // packed (highest hlc in this bundle)
  final List<ChangeRecord> changes;

  const SyncBundle({
    required this.schemaVersion,
    required this.deviceId,
    required this.fromHlc,
    required this.toHlc,
    required this.changes,
  });

  Map<String, dynamic> toJson() => {
    'schemaVersion': schemaVersion,
    'deviceId': deviceId,
    'fromHlc': fromHlc,
    'toHlc': toHlc,
    'changes': changes.map((c) => c.toJson()).toList(),
  };

  factory SyncBundle.fromJson(Map<String, dynamic> j) => SyncBundle(
    schemaVersion: j['schemaVersion'] as int,
    deviceId: j['deviceId'] as String,
    fromHlc: j['fromHlc'] as String,
    toHlc: j['toHlc'] as String,
    changes: (j['changes'] as List)
        .map((e) => ChangeRecord.fromJson((e as Map).cast<String, dynamic>()))
        .toList(),
  );
}
