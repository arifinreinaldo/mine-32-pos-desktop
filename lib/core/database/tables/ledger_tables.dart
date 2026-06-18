import 'package:drift/drift.dart';

import '../syncable_table.dart';

/// A payment received from a customer against their AR. Append-only **event**
/// (union-merged), so concurrent settlements on different devices both count.
@TableIndex(name: 'idx_receipt_customer', columns: {#customerId})
class CustomerReceipts extends Table with SyncableTable {
  TextColumn get customerId => text()();

  /// The sale this receipt is allocated to (null = general on-account payment).
  TextColumn get saleId => text().nullable()();
  IntColumn get amountMinor => integer()();
  TextColumn get method => text().withDefault(const Constant('cash'))();
  TextColumn get reference => text().nullable()();
}

/// A payment made to a supplier against AP. Append-only **event**.
@TableIndex(name: 'idx_suppay_supplier', columns: {#supplierId})
class SupplierPayments extends Table with SyncableTable {
  TextColumn get supplierId => text()();

  /// The purchase order this payment is allocated to (null = general).
  TextColumn get poId => text().nullable()();
  IntColumn get amountMinor => integer()();
  TextColumn get method => text().withDefault(const Constant('cash'))();
  TextColumn get reference => text().nullable()();
}
