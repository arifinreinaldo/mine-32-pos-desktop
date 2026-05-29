import 'dart:convert';

import 'package:drift/drift.dart';

import '../database/app_database.dart';
import '../time/hlc.dart';
import 'change_record.dart';
import 'hlc_service.dart';
import 'sync_entity.dart';
import 'transport/sync_transport.dart';

/// Outcome of a sync pass.
class SyncResult {
  final int exported;
  final int imported;
  const SyncResult({required this.exported, required this.imported});

  bool get changed => exported > 0 || imported > 0;

  @override
  String toString() => 'SyncResult(exported: $exported, imported: $imported)';
}

/// Orchestrates serverless sync: flush the local outbox to a bundle, import
/// peers' bundles, merge deterministically, then rebuild projections. Fully
/// optional to call — the app works identically if it never runs. See
/// `docs/SYNC.md`.
class SyncEngine {
  final AppDatabase db;
  final HlcService hlc;
  final SyncRegistry registry;
  final SyncTransport transport;
  final String deviceId;

  /// Callbacks that rebuild derived/projection tables after an import.
  final List<Future<void> Function()> reprojectors;

  SyncEngine({
    required this.db,
    required this.hlc,
    required this.registry,
    required this.transport,
    required this.deviceId,
    this.reprojectors = const [],
  });

  Future<SyncResult> sync() async {
    final exported = await export();
    final imported = await import();
    return SyncResult(exported: exported, imported: imported);
  }

  /// Bundle file name from a packed HLC, sanitised for Windows filenames
  /// (no ':'). Fixed-width fields keep names lexicographically sortable.
  static String bundleName(String packedHlc) =>
      'b-${packedHlc.replaceAll(':', '-')}.json';

  /// Flush unexported outbox entries into a single bundle. Returns #changes.
  Future<int> export() async {
    final rows =
        await (db.select(db.changeLog)
              ..where((t) => t.exported.equals(false))
              ..orderBy([(t) => OrderingTerm.asc(t.hlc)]))
            .get();
    if (rows.isEmpty) return 0;

    final records = [
      for (final r in rows)
        ChangeRecord(
          id: r.id,
          entityTable: r.entityTable,
          rowId: r.rowId,
          op: ChangeOp.values.byName(r.operation),
          payload: (jsonDecode(r.payload) as Map).cast<String, dynamic>(),
          hlc: Hlc.unpack(r.hlc),
          deviceId: r.deviceId,
          createdAt: r.createdAt,
        ),
    ];

    final toHlc = records.last.hlc.pack();
    final bundle = SyncBundle(
      schemaVersion: SyncBundle.currentSchemaVersion,
      deviceId: deviceId,
      fromHlc: records.first.hlc.pack(),
      toHlc: toHlc,
      changes: records,
    );

    final bytes = utf8.encode(jsonEncode(bundle.toJson()));
    await transport.putBundle(bundleName(toHlc), bytes);

    final ids = rows.map((r) => r.id).toList();
    await (db.update(db.changeLog)..where((t) => t.id.isIn(ids))).write(
      const ChangeLogCompanion(exported: Value(true)),
    );
    await _setMeta('sync.lastExport', toHlc);
    return records.length;
  }

  /// Pull peers' bundles and merge any not-yet-applied changes. Returns #applied.
  Future<int> import() async {
    final refs = await transport.listPeerBundles();

    // Group by producing device so each peer's cursor advances independently.
    final byPeer = <String, List<BundleRef>>{};
    for (final ref in refs) {
      byPeer.putIfAbsent(ref.deviceId, () => []).add(ref);
    }

    var applied = 0;
    for (final entry in byPeer.entries) {
      final cursorKey = 'sync.cursor.${entry.key}';
      final cursor = await _meta(cursorKey) ?? '';
      final peerRefs = entry.value..sort((a, b) => a.name.compareTo(b.name));

      var newCursor = cursor;
      // Only advance the cursor through a *contiguous* run of fully-applied
      // bundles; once a bundle is left partial (unknown entity), stop advancing
      // so it (and everything after) is retried on a later import.
      var contiguous = true;

      for (final ref in peerRefs) {
        if (ref.name.compareTo(cursor) <= 0) continue; // already consumed

        final bytes = await transport.getBundle(ref);
        final bundle = SyncBundle.fromJson(
          (jsonDecode(utf8.decode(bytes)) as Map).cast<String, dynamic>(),
        );

        var fullyApplied = true;
        for (final change in bundle.changes) {
          final entity = registry[change.entityTable];
          if (entity == null) {
            fullyApplied = false; // unknown entity (e.g. newer schema)
            continue;
          }
          if (await _applyOne(change, entity)) applied++;
        }

        if (fullyApplied && contiguous) {
          newCursor = ref.name;
        } else {
          contiguous = false;
        }
      }

      if (newCursor != cursor) await _setMeta(cursorKey, newCursor);
    }

    if (applied > 0) {
      for (final reproject in reprojectors) {
        await reproject();
      }
    }
    return applied;
  }

  /// Applies a single change idempotently. Returns true if it was newly applied.
  Future<bool> _applyOne(ChangeRecord change, SyncEntity entity) {
    return db.transaction(() async {
      final already = await (db.select(
        db.appliedChanges,
      )..where((t) => t.changeId.equals(change.id))).getSingleOrNull();
      if (already != null) return false;

      await hlc.observe(change.hlc);
      await entity.apply(db, change);
      await db
          .into(db.appliedChanges)
          .insert(
            AppliedChangesCompanion.insert(
              changeId: change.id,
              sourceDeviceId: change.deviceId,
              appliedAt: change.createdAt,
            ),
          );
      return true;
    });
  }

  Future<String?> _meta(String key) async {
    final row = await (db.select(
      db.syncMeta,
    )..where((t) => t.key.equals(key))).getSingleOrNull();
    return row?.value;
  }

  Future<void> _setMeta(String key, String value) async {
    await db
        .into(db.syncMeta)
        .insertOnConflictUpdate(
          SyncMetaCompanion.insert(key: key, value: value),
        );
  }
}
