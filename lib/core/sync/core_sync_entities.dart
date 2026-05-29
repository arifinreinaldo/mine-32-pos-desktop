import '../database/app_database.dart';
import 'sync_entity.dart';

/// Registers the always-present infrastructure entities. Feature modules call
/// their own `register*SyncEntities` to add catalog/inventory/sales/etc.
void registerCoreSyncEntities(SyncRegistry registry) {
  registry.register(
    SyncEntity<CompanySetting>(
      name: 'company_settings',
      kind: SyncKind.master,
      tableOf: (db) => db.companySettings,
      fromJson: CompanySetting.fromJson,
    ),
  );
  registry.register(
    SyncEntity<Device>(
      name: 'devices',
      kind: SyncKind.master,
      tableOf: (db) => db.devices,
      fromJson: Device.fromJson,
    ),
  );
}
