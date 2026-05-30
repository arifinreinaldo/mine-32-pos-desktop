import 'package:drift/drift.dart';

import '../syncable_table.dart';

/// A supplier / vendor. Master data (LWW). Tax id is the NPWP in Indonesia.
@TableIndex(name: 'idx_supplier_name', columns: {#name})
class Suppliers extends Table with SyncableTable {
  TextColumn get name => text()();
  TextColumn get phone => text().nullable()();
  TextColumn get email => text().nullable()();
  TextColumn get taxNumber => text().nullable()();
  TextColumn get address => text().nullable()();
  TextColumn get terms => text().nullable()();
  TextColumn get notes => text().nullable()();
}

/// A purchase order header. Mutable master data: draft -> ordered -> received.
@TableIndex(name: 'idx_po_supplier', columns: {#supplierId})
class PurchaseOrders extends Table with SyncableTable {
  TextColumn get number => text()();
  TextColumn get supplierId => text()();
  TextColumn get locationId => text()();

  /// draft | ordered | received | cancelled
  TextColumn get status => text().withDefault(const Constant('ordered'))();
  IntColumn get totalMinor => integer().withDefault(const Constant(0))();
  IntColumn get paidTotalMinor => integer().withDefault(const Constant(0))();
  IntColumn get orderedAt => integer().nullable()();
  IntColumn get receivedAt => integer().nullable()();
  TextColumn get notes => text().nullable()();
}

@TableIndex(name: 'idx_poline_po', columns: {#poId})
class PurchaseOrderLines extends Table with SyncableTable {
  TextColumn get poId => text()();
  TextColumn get variantId => text()();
  TextColumn get description => text()();
  IntColumn get qtyOrdered => integer()();
  IntColumn get qtyReceived => integer().withDefault(const Constant(0))();
  IntColumn get unitCostMinor => integer()();
  IntColumn get lineTotalMinor => integer()();
}
