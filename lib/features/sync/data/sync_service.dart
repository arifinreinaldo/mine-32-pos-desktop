import '../../../core/database/app_database.dart';
import '../../../core/di/app_services.dart';
import '../../../core/sync/sync_engine.dart';
import '../../../core/sync/transport/shared_folder_transport.dart';

/// Drives serverless sync from the UI: stores the shared-folder location, runs
/// the engine against a [SharedFolderTransport], and reports status. No backend.
class SyncService {
  static const _folderKey = 'sync.folder';
  static const _lastRunKey = 'sync.lastRun';

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
    return result;
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
