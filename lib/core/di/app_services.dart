import '../../features/accounting/data/accounting_repository.dart';
import '../../features/accounting/data/accounting_sync.dart';
import '../../features/catalog/data/catalog_sync.dart';
import '../../features/inventory/data/inventory_sync.dart';
import '../../features/sales/data/sales_sync.dart';
import '../database/app_database.dart';
import '../sync/change_log_writer.dart';
import '../sync/core_sync_entities.dart';
import '../sync/device_identity.dart';
import '../sync/hlc_service.dart';
import '../sync/sync_entity.dart';
import '../time/clock.dart';

/// Eagerly-initialised, app-wide singletons. Built once in `main()` (or a test)
/// and injected via Riverpod so every layer shares the same DB, clock and
/// sync wiring.
class AppServices {
  final AppDatabase db;
  final String deviceId;
  final Clock clock;
  final HlcService hlc;
  final ChangeLogWriter changeLog;
  final SyncRegistry registry;

  AppServices({
    required this.db,
    required this.deviceId,
    required this.clock,
    required this.hlc,
    required this.changeLog,
    required this.registry,
  });

  /// Open/prepare everything. Pass [database] (e.g. in-memory) and a fixed
  /// [clock] in tests.
  static Future<AppServices> initialize({
    AppDatabase? database,
    Clock clock = const SystemClock(),
  }) async {
    final db = database ?? AppDatabase();
    final deviceId = await DeviceIdentity(db).ensureId();
    final hlc = HlcService(db, clock, deviceId);
    await hlc.load();
    final changeLog = ChangeLogWriter(db, deviceId);
    final registry = SyncRegistry();
    registerCoreSyncEntities(registry);
    registerCatalogSyncEntities(registry);
    registerInventorySyncEntities(registry);
    registerSalesSyncEntities(registry);
    registerAccountingSyncEntities(registry);
    // Feature modules register their entities here as they are added.

    // Seed the chart of accounts + default PPN rate (idempotent).
    await AccountingRepository(
      db: db,
      changeLog: changeLog,
      hlcService: hlc,
      clock: clock,
    ).seedDefaults();

    return AppServices(
      db: db,
      deviceId: deviceId,
      clock: clock,
      hlc: hlc,
      changeLog: changeLog,
      registry: registry,
    );
  }

  Future<void> dispose() => db.close();
}
