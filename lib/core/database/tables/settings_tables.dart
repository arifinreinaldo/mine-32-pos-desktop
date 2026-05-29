import 'package:drift/drift.dart';

import '../syncable_table.dart';

/// Single-row (id = 'default') company configuration. Master data (LWW).
class CompanySettings extends Table with SyncableTable {
  TextColumn get name => text().withDefault(const Constant('My Auto Parts'))();
  TextColumn get legalName => text().nullable()();
  TextColumn get address => text().nullable()();
  TextColumn get phone => text().nullable()();
  TextColumn get email => text().nullable()();

  /// Company tax id. In Indonesia this is the NPWP.
  TextColumn get taxNumber => text().nullable()();

  /// Whether the business is a VAT-registered taxpayer (PKP) that charges PPN.
  BoolColumn get isPkp => boolean().withDefault(const Constant(false))();

  /// Whether listed prices already include tax (common in Indonesian retail).
  BoolColumn get taxInclusive => boolean().withDefault(const Constant(true))();
  TextColumn get defaultTaxRateId => text().nullable()();
  TextColumn get currency =>
      text().withLength(min: 3, max: 3).withDefault(const Constant('USD'))();
  IntColumn get currencyScale => integer().withDefault(const Constant(2))();
  TextColumn get receiptHeader => text().nullable()();
  TextColumn get receiptFooter => text().nullable()();
  TextColumn get logoPath => text().nullable()();
}
