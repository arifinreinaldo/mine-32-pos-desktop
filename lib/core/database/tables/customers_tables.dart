import 'package:drift/drift.dart';

import '../syncable_table.dart';

/// A customer / account. Master data (LWW). Tax id is the NPWP in Indonesia.
@TableIndex(name: 'idx_customer_name', columns: {#name})
class Customers extends Table with SyncableTable {
  TextColumn get name => text()();
  TextColumn get phone => text().nullable()();
  TextColumn get email => text().nullable()();
  TextColumn get taxNumber => text().nullable()();
  TextColumn get address => text().nullable()();
  IntColumn get creditLimitMinor => integer().withDefault(const Constant(0))();
  TextColumn get notes => text().nullable()();
}

/// A vehicle owned by a customer (for service history / fitment context).
@TableIndex(name: 'idx_custveh_customer', columns: {#customerId})
class CustomerVehicles extends Table with SyncableTable {
  TextColumn get customerId => text()();
  TextColumn get plate => text().nullable()();
  TextColumn get vin => text().nullable()();
  TextColumn get description => text().nullable()();
  TextColumn get notes => text().nullable()();
}
