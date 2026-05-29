import 'package:drift/drift.dart';

import '../syncable_table.dart';

/// Chart of accounts entry. Master data (LWW).
class Accounts extends Table with SyncableTable {
  TextColumn get code => text()();
  TextColumn get name => text()();

  /// asset | liability | equity | income | expense
  TextColumn get type => text()();
  TextColumn get subtype => text().nullable()();
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();
}

/// A tax rate. For Indonesia this is typically PPN (VAT) at 11%/12%. Master data.
class TaxRates extends Table with SyncableTable {
  TextColumn get name => text()();

  /// Rate in basis points (1100 = 11%, 1200 = 12%).
  IntColumn get basisPoints => integer()();

  /// Whether listed prices already include this tax (common in ID retail).
  BoolColumn get inclusive => boolean().withDefault(const Constant(true))();
  BoolColumn get isDefault => boolean().withDefault(const Constant(false))();

  /// PPN (VAT) | PPnBM | none ...
  TextColumn get taxType => text().withDefault(const Constant('PPN'))();
}

/// A balanced double-entry journal (immutable once posted). Event entity.
@TableIndex(name: 'idx_journal_ref', columns: {#refType, #refId})
class Journals extends Table with SyncableTable {
  IntColumn get date => integer()(); // epoch ms (UTC)

  /// sale | purchase | payment | adjustment | manual
  TextColumn get source => text()();
  TextColumn get refType => text().nullable()();
  TextColumn get refId => text().nullable()();
  TextColumn get memo => text().nullable()();
  BoolColumn get posted => boolean().withDefault(const Constant(true))();
}

/// One leg of a journal. Sum(debit) must equal Sum(credit) per journal.
@TableIndex(name: 'idx_jline_journal', columns: {#journalId})
@TableIndex(name: 'idx_jline_account', columns: {#accountId})
class JournalLines extends Table with SyncableTable {
  TextColumn get journalId => text()();
  TextColumn get accountId => text()();
  IntColumn get debitMinor => integer().withDefault(const Constant(0))();
  IntColumn get creditMinor => integer().withDefault(const Constant(0))();
  TextColumn get description => text().nullable()();
}
