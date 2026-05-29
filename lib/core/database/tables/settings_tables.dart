import 'package:drift/drift.dart';

import '../syncable_table.dart';

/// Single-row (id = 'default') company configuration. Master data (LWW).
class CompanySettings extends Table with SyncableTable {
  TextColumn get name => text().withDefault(const Constant('My Auto Parts'))();
  TextColumn get legalName => text().nullable()();
  TextColumn get address => text().nullable()();
  TextColumn get phone => text().nullable()();
  TextColumn get email => text().nullable()();
  TextColumn get taxNumber => text().nullable()();
  TextColumn get currency =>
      text().withLength(min: 3, max: 3).withDefault(const Constant('USD'))();
  IntColumn get currencyScale => integer().withDefault(const Constant(2))();
  TextColumn get receiptHeader => text().nullable()();
  TextColumn get receiptFooter => text().nullable()();
  TextColumn get logoPath => text().nullable()();
}
