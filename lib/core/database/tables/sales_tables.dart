import 'package:drift/drift.dart';

import '../syncable_table.dart';

// Sales are recorded at completion as immutable **event** rows (sale + lines +
// payments), so they union-merge across devices with no conflicts. (Parked
// drafts, which would be mutable, are a later addition.)

/// A completed sale (header). Money fields are integer minor units.
class Sales extends Table with SyncableTable {
  TextColumn get number => text()();
  TextColumn get customerId => text().nullable()();
  TextColumn get locationId => text()();
  TextColumn get status => text().withDefault(const Constant('completed'))();
  IntColumn get subtotalMinor => integer().withDefault(const Constant(0))();
  IntColumn get discountMinor => integer().withDefault(const Constant(0))();
  IntColumn get taxTotalMinor => integer().withDefault(const Constant(0))();
  IntColumn get totalMinor => integer().withDefault(const Constant(0))();
  IntColumn get paidTotalMinor => integer().withDefault(const Constant(0))();
  IntColumn get postedAt => integer().nullable()();

  // Tax / faktur (Indonesia CoreTax) — subtotalMinor is the DPP (tax base) and
  // taxTotalMinor is the PPN. Buyer details support issuing a tax invoice.
  TextColumn get buyerName => text().nullable()();
  TextColumn get buyerNpwp => text().nullable()();
  TextColumn get fakturNumber => text().nullable()();
}

@TableIndex(name: 'idx_saleline_sale', columns: {#saleId})
class SaleLines extends Table with SyncableTable {
  TextColumn get saleId => text()();
  TextColumn get variantId => text().nullable()();
  TextColumn get description => text()();
  IntColumn get qty => integer()();
  IntColumn get unitPriceMinor => integer()();
  IntColumn get discountMinor => integer().withDefault(const Constant(0))();
  IntColumn get taxMinor => integer().withDefault(const Constant(0))();
  IntColumn get lineTotalMinor => integer()();
  IntColumn get unitCostMinor => integer().withDefault(const Constant(0))();
}

@TableIndex(name: 'idx_payment_sale', columns: {#saleId})
class Payments extends Table with SyncableTable {
  TextColumn get saleId => text()();

  /// cash | card | transfer | store_credit
  TextColumn get method => text()();
  IntColumn get amountMinor => integer()();
  IntColumn get tenderedMinor => integer().withDefault(const Constant(0))();
  IntColumn get changeMinor => integer().withDefault(const Constant(0))();
  TextColumn get reference => text().nullable()();
}
