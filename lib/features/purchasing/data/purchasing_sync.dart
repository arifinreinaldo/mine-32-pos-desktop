import '../../../core/database/app_database.dart';
import '../../../core/sync/sync_entity.dart';

/// Registers purchasing tables with the sync engine (master data, LWW).
void registerPurchasingSyncEntities(SyncRegistry registry) {
  registry.register(
    SyncEntity<Supplier>(
      name: 'suppliers',
      kind: SyncKind.master,
      tableOf: (db) => db.suppliers,
      fromJson: Supplier.fromJson,
    ),
  );
  registry.register(
    SyncEntity<PurchaseOrder>(
      name: 'purchase_orders',
      kind: SyncKind.master,
      tableOf: (db) => db.purchaseOrders,
      fromJson: PurchaseOrder.fromJson,
    ),
  );
  registry.register(
    SyncEntity<PurchaseOrderLine>(
      name: 'purchase_order_lines',
      kind: SyncKind.master,
      tableOf: (db) => db.purchaseOrderLines,
      fromJson: PurchaseOrderLine.fromJson,
    ),
  );
  registry.register(
    SyncEntity<SupplierPayment>(
      name: 'supplier_payments',
      kind: SyncKind.event,
      tableOf: (db) => db.supplierPayments,
      fromJson: SupplierPayment.fromJson,
    ),
  );
}
