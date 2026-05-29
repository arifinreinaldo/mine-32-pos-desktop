import '../../../core/database/app_database.dart';
import '../../../core/sync/sync_entity.dart';

/// Registers inventory tables with the sync engine.
///
/// - `locations` is master data (LWW).
/// - `stock_movements` is an **event** entity: append-only and merged by
///   set-union (insert-if-absent), so concurrent offline stock changes all
///   survive sync. On-hand is the SUM of movements (a projection), never synced.
void registerInventorySyncEntities(SyncRegistry registry) {
  registry.register(
    SyncEntity<Location>(
      name: 'locations',
      kind: SyncKind.master,
      tableOf: (db) => db.locations,
      fromJson: Location.fromJson,
    ),
  );
  registry.register(
    SyncEntity<StockMovement>(
      name: 'stock_movements',
      kind: SyncKind.event,
      tableOf: (db) => db.stockMovements,
      fromJson: StockMovement.fromJson,
    ),
  );
}
