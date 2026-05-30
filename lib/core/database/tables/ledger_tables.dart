import 'package:drift/drift.dart';

import '../syncable_table.dart';

/// A payment received from a customer against their AR. Append-only **event**
/// (union-merged), so concurrent settlements on different devices both count.
@TableIndex(name: 'idx_receipt_customer', columns: {#customerId})
class CustomerReceipts extends Table with SyncableTable {
  TextColumn get customerId => text()();
  IntColumn get amountMinor => integer()();
  TextColumn get method => text().withDefault(const Constant('cash'))();
  TextColumn get reference => text().nullable()();
}

/// A payment made to a supplier against AP. Append-only **event**.
@TableIndex(name: 'idx_suppay_supplier', columns: {#supplierId})
class SupplierPayments extends Table with SyncableTable {
  TextColumn get supplierId => text()();
  IntColumn get amountMinor => integer()();
  TextColumn get method => text().withDefault(const Constant('cash'))();
  TextColumn get reference => text().nullable()();
}
