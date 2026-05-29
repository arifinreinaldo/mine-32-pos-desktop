import '../../../core/database/app_database.dart';
import '../../../core/sync/sync_entity.dart';

/// Registers accounting tables with the sync engine. Accounts and tax rates are
/// master data (LWW); journals and their lines are immutable events (union).
void registerAccountingSyncEntities(SyncRegistry registry) {
  registry.register(
    SyncEntity<Account>(
      name: 'accounts',
      kind: SyncKind.master,
      tableOf: (db) => db.accounts,
      fromJson: Account.fromJson,
    ),
  );
  registry.register(
    SyncEntity<TaxRate>(
      name: 'tax_rates',
      kind: SyncKind.master,
      tableOf: (db) => db.taxRates,
      fromJson: TaxRate.fromJson,
    ),
  );
  registry.register(
    SyncEntity<Journal>(
      name: 'journals',
      kind: SyncKind.event,
      tableOf: (db) => db.journals,
      fromJson: Journal.fromJson,
    ),
  );
  registry.register(
    SyncEntity<JournalLine>(
      name: 'journal_lines',
      kind: SyncKind.event,
      tableOf: (db) => db.journalLines,
      fromJson: JournalLine.fromJson,
    ),
  );
}
