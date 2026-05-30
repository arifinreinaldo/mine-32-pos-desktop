import '../../../core/database/app_database.dart';
import '../../../core/sync/sync_entity.dart';

/// Registers customer tables with the sync engine (master data, LWW).
void registerCustomerSyncEntities(SyncRegistry registry) {
  registry.register(
    SyncEntity<Customer>(
      name: 'customers',
      kind: SyncKind.master,
      tableOf: (db) => db.customers,
      fromJson: Customer.fromJson,
    ),
  );
  registry.register(
    SyncEntity<CustomerVehicle>(
      name: 'customer_vehicles',
      kind: SyncKind.master,
      tableOf: (db) => db.customerVehicles,
      fromJson: CustomerVehicle.fromJson,
    ),
  );
  registry.register(
    SyncEntity<CustomerReceipt>(
      name: 'customer_receipts',
      kind: SyncKind.event,
      tableOf: (db) => db.customerReceipts,
      fromJson: CustomerReceipt.fromJson,
    ),
  );
}
