import '../../../core/database/app_database.dart';
import '../../../core/sync/sync_entity.dart';

/// Registers sales tables with the sync engine. Completed sales are immutable
/// **event** entities, so they union-merge across devices conflict-free.
void registerSalesSyncEntities(SyncRegistry registry) {
  registry.register(
    SyncEntity<Sale>(
      name: 'sales',
      kind: SyncKind.event,
      tableOf: (db) => db.sales,
      fromJson: Sale.fromJson,
    ),
  );
  registry.register(
    SyncEntity<SaleLine>(
      name: 'sale_lines',
      kind: SyncKind.event,
      tableOf: (db) => db.saleLines,
      fromJson: SaleLine.fromJson,
    ),
  );
  registry.register(
    SyncEntity<Payment>(
      name: 'payments',
      kind: SyncKind.event,
      tableOf: (db) => db.payments,
      fromJson: Payment.fromJson,
    ),
  );
}
