import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../../../core/database/app_database.dart';
import '../../../core/database/sync_repository.dart';
import '../../../core/money/money.dart';
import '../domain/accounting_models.dart';
import '../domain/coretax_csv.dart';

/// Double-entry accounting: chart of accounts, balanced journals, posting rules,
/// trial balance and the PPN (VAT) summary used for Indonesian CoreTax.
class AccountingRepository extends SyncRepository {
  final Uuid _uuid;

  AccountingRepository({
    required super.db,
    required super.changeLog,
    required super.hlcService,
    required super.clock,
    Uuid? uuid,
  }) : _uuid = uuid ?? const Uuid();

  // --- Seeding ---

  Future<void> seedDefaults() async {
    await seedChartOfAccounts();
    await seedDefaultTaxRate();
  }

  Future<void> seedChartOfAccounts() async {
    final count = await db.accounts.count().getSingle();
    if (count > 0) return;
    const seed = <List<String>>[
      [AccountCode.cash, 'Cash', 'asset'],
      [AccountCode.bank, 'Bank', 'asset'],
      [AccountCode.receivable, 'Accounts Receivable', 'asset'],
      [AccountCode.inventory, 'Inventory', 'asset'],
      [AccountCode.accountsPayable, 'Accounts Payable', 'liability'],
      [AccountCode.ppnOutput, 'PPN Output (VAT Payable)', 'liability'],
      [AccountCode.ownerEquity, 'Owner Equity', 'equity'],
      [AccountCode.salesRevenue, 'Sales Revenue', 'income'],
      [AccountCode.cogs, 'Cost of Goods Sold', 'expense'],
      [AccountCode.inventoryAdjustment, 'Inventory Adjustments', 'expense'],
    ];
    for (final a in seed) {
      final id = _uuid.v7();
      await writeSyncable<Account>(
        entityTable: 'accounts',
        table: db.accounts,
        rowId: id,
        build: (hlc, now) => Account(
          id: id,
          createdAt: now,
          updatedAt: now,
          updatedHlc: hlc.pack(),
          code: a[0],
          name: a[1],
          type: a[2],
          isActive: true,
        ),
      );
    }
  }

  Future<void> seedDefaultTaxRate() async {
    final count = await db.taxRates.count().getSingle();
    if (count > 0) return;
    final id = _uuid.v7();
    await writeSyncable<TaxRate>(
      entityTable: 'tax_rates',
      table: db.taxRates,
      rowId: id,
      build: (hlc, now) => TaxRate(
        id: id,
        createdAt: now,
        updatedAt: now,
        updatedHlc: hlc.pack(),
        name: 'PPN 11%',
        basisPoints: 1100,
        inclusive: true,
        isDefault: true,
        taxType: 'PPN',
      ),
    );
  }

  Future<Account?> accountByCode(String code) {
    return (db.select(db.accounts)
          ..where((t) => t.code.equals(code) & t.deletedAt.isNull())
          ..limit(1))
        .getSingleOrNull();
  }

  Future<TaxRate?> defaultTaxRate() async {
    final def =
        await (db.select(db.taxRates)
              ..where((t) => t.isDefault.equals(true) & t.deletedAt.isNull())
              ..limit(1))
            .getSingleOrNull();
    if (def != null) return def;
    return (db.select(db.taxRates)
          ..where((t) => t.deletedAt.isNull())
          ..limit(1))
        .getSingleOrNull();
  }

  // --- Posting ---

  /// Posts a balanced journal. Throws if debits != credits. Returns journal id.
  Future<String> postJournal({
    required int date,
    required String source,
    required List<JournalLineInput> lines,
    String? refType,
    String? refId,
    String? memo,
  }) async {
    final totalDebit = lines.fold(0, (s, l) => s + l.debitMinor);
    final totalCredit = lines.fold(0, (s, l) => s + l.creditMinor);
    if (totalDebit != totalCredit) {
      throw StateError(
        'Unbalanced journal: debit $totalDebit != credit $totalCredit',
      );
    }
    return db.transaction(() async {
      final journalId = _uuid.v7();
      await writeSyncable<Journal>(
        entityTable: 'journals',
        table: db.journals,
        rowId: journalId,
        build: (hlc, now) => Journal(
          id: journalId,
          createdAt: now,
          updatedAt: now,
          updatedHlc: hlc.pack(),
          date: date,
          source: source,
          refType: refType,
          refId: refId,
          memo: memo,
          posted: true,
        ),
      );
      for (final line in lines) {
        final id = _uuid.v7();
        await writeSyncable<JournalLine>(
          entityTable: 'journal_lines',
          table: db.journalLines,
          rowId: id,
          build: (hlc, now) => JournalLine(
            id: id,
            createdAt: now,
            updatedAt: now,
            updatedHlc: hlc.pack(),
            journalId: journalId,
            accountId: line.accountId,
            debitMinor: line.debitMinor,
            creditMinor: line.creditMinor,
            description: line.description,
          ),
        );
      }
      return journalId;
    });
  }

  /// Posts the standard sale journal (revenue, PPN, COGS). The debit side is
  /// Cash, Bank or — for on-account/credit sales — Accounts Receivable.
  Future<void> postSaleJournal({
    required String saleId,
    required int date,
    required String method,
    required int totalMinor,
    required int dppMinor,
    required int ppnMinor,
    required int cogsMinor,
  }) async {
    final debitCode = switch (method) {
      'account' => AccountCode.receivable,
      'cash' => AccountCode.cash,
      _ => AccountCode.bank,
    };
    final pay = await accountByCode(debitCode);
    final salesAcc = await accountByCode(AccountCode.salesRevenue);
    final ppnAcc = await accountByCode(AccountCode.ppnOutput);
    final cogsAcc = await accountByCode(AccountCode.cogs);
    final invAcc = await accountByCode(AccountCode.inventory);
    if (pay == null ||
        salesAcc == null ||
        ppnAcc == null ||
        cogsAcc == null ||
        invAcc == null) {
      return; // chart of accounts not seeded; skip posting
    }

    final lines = <JournalLineInput>[
      JournalLineInput(
        accountId: pay.id,
        debitMinor: totalMinor,
        description: 'Sale payment',
      ),
      JournalLineInput(
        accountId: salesAcc.id,
        creditMinor: dppMinor,
        description: 'Sales revenue',
      ),
      if (ppnMinor > 0)
        JournalLineInput(
          accountId: ppnAcc.id,
          creditMinor: ppnMinor,
          description: 'PPN output',
        ),
    ];
    if (cogsMinor > 0) {
      lines.add(
        JournalLineInput(
          accountId: cogsAcc.id,
          debitMinor: cogsMinor,
          description: 'COGS',
        ),
      );
      lines.add(
        JournalLineInput(
          accountId: invAcc.id,
          creditMinor: cogsMinor,
          description: 'Inventory',
        ),
      );
    }

    await postJournal(
      date: date,
      source: 'sale',
      refType: 'sale',
      refId: saleId,
      memo: 'Sale',
      lines: lines,
    );
  }

  // --- Reports ---

  Stream<List<TrialBalanceRow>> watchTrialBalance() {
    final a = db.accounts;
    final jl = db.journalLines;
    final debit = jl.debitMinor.sum();
    final credit = jl.creditMinor.sum();
    final statement =
        db.select(a).join([
            leftOuterJoin(
              jl,
              jl.accountId.equalsExp(a.id) & jl.deletedAt.isNull(),
            ),
          ])
          ..addColumns([debit, credit])
          ..where(a.deletedAt.isNull())
          ..groupBy([a.id])
          ..orderBy([OrderingTerm.asc(a.code)]);
    return statement.watch().map(
      (rows) => rows.map((row) {
        final acc = row.readTable(a);
        return TrialBalanceRow(
          accountId: acc.id,
          code: acc.code,
          name: acc.name,
          type: acc.type,
          debit: Money(row.read(debit) ?? 0),
          credit: Money(row.read(credit) ?? 0),
        );
      }).toList(),
    );
  }

  /// PPN summary over completed sales in [fromMs, toMs) — for CoreTax reporting.
  Future<TaxSummary> taxSummary({int? fromMs, int? toMs}) async {
    final s = db.sales;
    final dpp = s.subtotalMinor.sum();
    final ppn = s.taxTotalMinor.sum();
    final total = s.totalMinor.sum();
    final count = s.id.count();

    var predicate = s.deletedAt.isNull() & s.status.equals('completed');
    if (fromMs != null) {
      predicate = predicate & s.createdAt.isBiggerOrEqualValue(fromMs);
    }
    if (toMs != null) {
      predicate = predicate & s.createdAt.isSmallerThanValue(toMs);
    }

    final row =
        await (db.selectOnly(s)
              ..addColumns([dpp, ppn, total, count])
              ..where(predicate))
            .getSingleOrNull();

    return TaxSummary(
      salesCount: row?.read(count) ?? 0,
      dpp: Money(row?.read(dpp) ?? 0),
      ppn: Money(row?.read(ppn) ?? 0),
      grandTotal: Money(row?.read(total) ?? 0),
    );
  }

  /// Completed sales in a period (for the CoreTax faktur detail / export).
  Future<List<Sale>> salesForTaxPeriod({int? fromMs, int? toMs}) {
    var predicate =
        db.sales.deletedAt.isNull() & db.sales.status.equals('completed');
    if (fromMs != null) {
      predicate = predicate & db.sales.createdAt.isBiggerOrEqualValue(fromMs);
    }
    if (toMs != null) {
      predicate = predicate & db.sales.createdAt.isSmallerThanValue(toMs);
    }
    return (db.select(db.sales)
          ..where((_) => predicate)
          ..orderBy([(t) => OrderingTerm.asc(t.createdAt)]))
        .get();
  }

  /// Faktur rows for a CoreTax-style PPN export over a period.
  Future<List<FakturRow>> fakturRowsForPeriod({int? fromMs, int? toMs}) async {
    final sales = await salesForTaxPeriod(fromMs: fromMs, toMs: toMs);
    return [
      for (final s in sales)
        FakturRow(
          number: s.number,
          dateMs: s.createdAt,
          buyerName: s.buyerName,
          buyerNpwp: s.buyerNpwp,
          fakturNumber: s.fakturNumber,
          dppMinor: s.subtotalMinor,
          ppnMinor: s.taxTotalMinor,
          totalMinor: s.totalMinor,
        ),
    ];
  }
}
