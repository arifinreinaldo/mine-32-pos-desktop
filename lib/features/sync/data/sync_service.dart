import 'dart:convert';

import '../../../core/database/app_database.dart';
import '../../../core/di/app_services.dart';
import '../../../core/sync/sync_engine.dart';
import '../../../core/sync/transport/shared_folder_transport.dart';

/// One recorded sync pass, for the Sync screen's history.
class SyncRun {
  final int ranAtMs;
  final int exported;
  final int imported;
  const SyncRun({
    required this.ranAtMs,
    required this.exported,
    required this.imported,
  });

  Map<String, dynamic> toJson() => {
    'at': ranAtMs,
    'exp': exported,
    'imp': imported,
  };

  factory SyncRun.fromJson(Map<String, dynamic> j) => SyncRun(
    ranAtMs: (j['at'] as num).toInt(),
    exported: (j['exp'] as num).toInt(),
    imported: (j['imp'] as num).toInt(),
  );
}

/// Drives serverless sync from the UI: stores the shared-folder location, runs
/// the engine against a [SharedFolderTransport], and reports status. No backend.
class SyncService {
  static const _folderKey = 'sync.folder';
  static const _lastRunKey = 'sync.lastRun';
  static const _historyKey = 'sync.history';
  static const _historyLimit = 20;

  final AppServices services;
  SyncService(this.services);

  AppDatabase get _db => services.db;

  Future<String?> folderPath() => _meta(_folderKey);
  Future<void> setFolderPath(String path) => _setMeta(_folderKey, path);
  Future<String?> lastRun() => _meta(_lastRunKey);

  /// Number of local changes not yet written into an export bundle.
  Future<int> pendingCount() async {
    final rows = await (_db.select(
      _db.changeLog,
    )..where((t) => t.exported.equals(false))).get();
    return rows.length;
  }

  /// Export local changes and import peers' — through the configured folder.
  Future<SyncResult> syncNow() async {
    final path = await folderPath();
    if (path == null || path.isEmpty) {
      throw StateError('No sync folder configured');
    }
    final engine = SyncEngine(
      db: services.db,
      hlc: services.hlc,
      registry: services.registry,
      transport: SharedFolderTransport(
        rootPath: path,
        selfDeviceId: services.deviceId,
      ),
      deviceId: services.deviceId,
    );
    final result = await engine.sync();
    await _setMeta(_lastRunKey, DateTime.now().toIso8601String());
    await recordRun(result);
    return result;
  }

  /// Append a sync pass to the local history (newest-first, capped). Kept device
  /// -local in `sync_meta` — it is not itself synced.
  Future<void> recordRun(SyncResult result, {DateTime? at}) async {
    final runs = await recentRuns();
    final updated = [
      SyncRun(
        ranAtMs: (at ?? DateTime.now()).millisecondsSinceEpoch,
        exported: result.exported,
        imported: result.imported,
      ),
      ...runs,
    ].take(_historyLimit).toList();
    await _setMeta(
      _historyKey,
      jsonEncode([for (final r in updated) r.toJson()]),
    );
  }

  /// Recent sync passes, newest first.
  Future<List<SyncRun>> recentRuns() async {
    final raw = await _meta(_historyKey);
    if (raw == null || raw.isEmpty) return const [];
    final list = jsonDecode(raw);
    if (list is! List) return const [];
    return [
      for (final e in list)
        SyncRun.fromJson((e as Map).cast<String, dynamic>()),
    ];
  }

  /// LWW conflict overrides recorded during imports, newest first.
  Future<List<ConflictRecord>> recentConflicts() async {
    final raw = await _meta('sync.conflicts');
    if (raw == null || raw.isEmpty) return const [];
    final list = jsonDecode(raw);
    if (list is! List) return const [];
    return [
      for (final e in list)
        ConflictRecord.fromJson((e as Map).cast<String, dynamic>()),
    ];
  }

  Future<String?> _meta(String key) async {
    final row =
        await (_db.select(_db.syncMeta)
              ..where((t) => t.key.equals(key))
              ..limit(1))
            .getSingleOrNull();
    return row?.value;
  }

  Future<void> _setMeta(String key, String value) async {
    await _db
        .into(_db.syncMeta)
        .insertOnConflictUpdate(
          SyncMetaCompanion.insert(key: key, value: value),
        );
  }
}
