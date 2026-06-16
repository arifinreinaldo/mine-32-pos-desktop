import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../../../core/database/app_database.dart';
import '../../../core/database/sync_repository.dart';
import '../../../core/money/money.dart';
import '../../../core/sync/change_record.dart';
import '../domain/accounting_models.dart';
import '../domain/coretax_csv.dart';
import '../domain/coretax_xml.dart';

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
      [AccountCode.ppnInput, 'PPN Input (VAT Receivable)', 'asset'],
      [AccountCode.inventory, 'Inventory', 'asset'],
      [AccountCode.accountsPayable, 'Accounts Payable', 'liability'],
      [AccountCode.ppnOutput, 'PPN Output (VAT Payable)', 'liability'],
      [AccountCode.ownerEquity, 'Owner Equity', 'equity'],
      [AccountCode.salesRevenue, 'Sales Revenue', 'income'],
      [AccountCode.cogs, 'Cost of Goods Sold', 'expense'],
      [AccountCode.inventoryAdjustment, 'Inventory Adjustments', 'expense'],
    ];
    for (final a in seed) {
      // Deterministic id (stable across devices) so two devices seeding the
      // same chart of accounts converge to one row per code on sync/restore
      // instead of duplicating by code.
      final id = 'account:${a[0]}';
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
    // Deterministic id so the seeded PPN rate converges across devices.
    const id = 'taxrate:default';
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

  /// All tax rates (newest-relevant first: default, then by name).
  Stream<List<TaxRate>> watchTaxRates() {
    return (db.select(db.taxRates)
          ..where((t) => t.deletedAt.isNull())
          ..orderBy([
            (t) => OrderingTerm.desc(t.isDefault),
            (t) => OrderingTerm.asc(t.name),
          ]))
        .watch();
  }

  /// Creates or updates a tax rate. When [isDefault] is set, the flag is cleared
  /// on every other rate so exactly one default exists.
  Future<String> saveTaxRate({
    String? id,
    required String name,
    required int basisPoints,
    bool inclusive = true,
    bool isDefault = false,
    String taxType = 'PPN',
  }) async {
    final rateId = id ?? _uuid.v7();
    final createdAt = id == null
        ? clock.nowMillis()
        : await existingCreatedAt(db.taxRates, rateId) ?? clock.nowMillis();

    if (isDefault) {
      final others = await (db.select(
        db.taxRates,
      )..where((t) => t.isDefault.equals(true) & t.deletedAt.isNull())).get();
      for (final o in others) {
        if (o.id == rateId) continue;
        await writeSyncable<TaxRate>(
          entityTable: 'tax_rates',
          table: db.taxRates,
          rowId: o.id,
          build: (hlc, now) => o.copyWith(
            isDefault: false,
            updatedAt: now,
            updatedHlc: hlc.pack(),
          ),
        );
      }
    }

    await writeSyncable<TaxRate>(
      entityTable: 'tax_rates',
      table: db.taxRates,
      rowId: rateId,
      build: (hlc, now) => TaxRate(
        id: rateId,
        createdAt: createdAt,
        updatedAt: now,
        updatedHlc: hlc.pack(),
        name: name,
        basisPoints: basisPoints,
        inclusive: inclusive,
        isDefault: isDefault,
        taxType: taxType,
      ),
    );
    return rateId;
  }

  /// Tombstones a tax rate so the deletion replicates.
  Future<void> deleteTaxRate(String id) async {
    final row =
        await (db.select(db.taxRates)
              ..where((t) => t.id.equals(id))
              ..limit(1))
            .getSingleOrNull();
    if (row == null) return;
    await writeSyncable<TaxRate>(
      entityTable: 'tax_rates',
      table: db.taxRates,
      rowId: id,
      op: ChangeOp.delete,
      build: (hlc, now) => row.copyWith(
        deletedAt: Value(now),
        updatedAt: now,
        updatedHlc: hlc.pack(),
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

  /// Posts a user-entered ("manual") journal. Thin wrapper over [postJournal]
  /// that tags the source; the balanced-debits/credits invariant still applies.
  Future<String> postManualJournal({
    required int date,
    required List<JournalLineInput> lines,
    String? memo,
  }) {
    return postJournal(
      date: date,
      source: 'manual',
      refType: 'manual',
      memo: memo,
      lines: lines,
    );
  }

  /// Active accounts, ordered by code — for pickers and the chart of accounts.
  Future<List<Account>> listAccounts() {
    return (db.select(db.accounts)
          ..where((t) => t.deletedAt.isNull() & t.isActive.equals(true))
          ..orderBy([(t) => OrderingTerm.asc(t.code)]))
        .get();
  }

  /// Recent journals (most recent first) with their posted total, for the
  /// journal browser. Optional date window filters on the journal date.
  Stream<List<JournalSummary>> watchJournals({
    int? fromMs,
    int? toMs,
    int limit = 200,
  }) {
    final j = db.journals;
    final jl = db.journalLines;
    final debit = jl.debitMinor.sum();
    final statement =
        db.select(j).join([
            leftOuterJoin(
              jl,
              jl.journalId.equalsExp(j.id) & jl.deletedAt.isNull(),
            ),
          ])
          ..addColumns([debit])
          ..where(j.deletedAt.isNull())
          ..groupBy([j.id])
          ..orderBy([OrderingTerm.desc(j.date), OrderingTerm.desc(j.createdAt)])
          ..limit(limit);
    if (fromMs != null) {
      statement.where(j.date.isBiggerOrEqualValue(fromMs));
    }
    if (toMs != null) {
      statement.where(j.date.isSmallerThanValue(toMs));
    }
    return statement.watch().map(
      (rows) => rows.map((row) {
        final journal = row.readTable(j);
        return JournalSummary(
          id: journal.id,
          dateMs: journal.date,
          source: journal.source,
          memo: journal.memo,
          refType: journal.refType,
          total: Money(row.read(debit) ?? 0),
        );
      }).toList(),
    );
  }

  /// The posted lines of one journal, joined to account code/name.
  Future<List<JournalLineView>> journalLines(String journalId) async {
    final jl = db.journalLines;
    final a = db.accounts;
    final rows =
        await (db.select(jl).join([innerJoin(a, a.id.equalsExp(jl.accountId))])
              ..where(jl.journalId.equals(journalId) & jl.deletedAt.isNull())
              ..orderBy([OrderingTerm.asc(a.code)]))
            .get();
    return rows.map((row) {
      final line = row.readTable(jl);
      final acc = row.readTable(a);
      return JournalLineView(
        accountCode: acc.code,
        accountName: acc.name,
        debit: Money(line.debitMinor),
        credit: Money(line.creditMinor),
        description: line.description,
      );
    }).toList();
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

  /// Reverses a sale for a return/refund: Dr Sales Revenue (DPP) + Dr PPN Output
  /// (PPN) + Cr Cash/Bank (total refunded); and Dr Inventory + Cr COGS (cost of
  /// the restocked goods). Mirrors [postSaleJournal] with the signs flipped.
  Future<void> postReturnJournal({
    required String returnId,
    required int date,
    required String method, // cash | bank
    required int totalMinor,
    required int dppMinor,
    required int ppnMinor,
    required int cogsMinor,
  }) async {
    if (totalMinor <= 0) return;
    final refundFrom = await accountByCode(
      method == 'bank' ? AccountCode.bank : AccountCode.cash,
    );
    final salesAcc = await accountByCode(AccountCode.salesRevenue);
    final ppnAcc = await accountByCode(AccountCode.ppnOutput);
    final cogsAcc = await accountByCode(AccountCode.cogs);
    final invAcc = await accountByCode(AccountCode.inventory);
    if (refundFrom == null ||
        salesAcc == null ||
        ppnAcc == null ||
        cogsAcc == null ||
        invAcc == null) {
      return;
    }

    final lines = <JournalLineInput>[
      JournalLineInput(
        accountId: salesAcc.id,
        debitMinor: dppMinor,
        description: 'Sales return (revenue)',
      ),
      if (ppnMinor > 0)
        JournalLineInput(
          accountId: ppnAcc.id,
          debitMinor: ppnMinor,
          description: 'PPN output reversal',
        ),
      JournalLineInput(
        accountId: refundFrom.id,
        creditMinor: totalMinor,
        description: 'Refund',
      ),
    ];
    if (cogsMinor > 0) {
      lines.add(
        JournalLineInput(
          accountId: invAcc.id,
          debitMinor: cogsMinor,
          description: 'Inventory restocked',
        ),
      );
      lines.add(
        JournalLineInput(
          accountId: cogsAcc.id,
          creditMinor: cogsMinor,
          description: 'COGS reversal',
        ),
      );
    }

    await postJournal(
      date: date,
      source: 'return',
      refType: 'sales_return',
      refId: returnId,
      memo: 'Sales return',
      lines: lines,
    );
  }

  /// Goods-receipt journal for a received purchase order:
  /// Dr Inventory · Cr Accounts Payable.
  /// Goods-receipt journal. [totalMinor] is the gross payable to the supplier
  /// (= Accounts Payable). When [ppnMinor] > 0 (a PKP buying taxable goods) the
  /// recoverable input VAT is split out: Dr Inventory (net) · Dr PPN Input (VAT)
  /// · Cr AP (gross). Otherwise it's the plain Dr Inventory · Cr AP.
  Future<void> postPurchaseJournal({
    required String poId,
    required int date,
    required int totalMinor,
    int ppnMinor = 0,
  }) async {
    if (totalMinor <= 0) return;
    final inv = await accountByCode(AccountCode.inventory);
    final ap = await accountByCode(AccountCode.accountsPayable);
    if (inv == null || ap == null) return;
    final ppnIn = ppnMinor > 0
        ? await accountByCode(AccountCode.ppnInput)
        : null;
    final invDebit = ppnIn != null ? totalMinor - ppnMinor : totalMinor;
    await postJournal(
      date: date,
      source: 'purchase',
      refType: 'purchase_order',
      refId: poId,
      memo: 'Goods receipt',
      lines: [
        JournalLineInput(
          accountId: inv.id,
          debitMinor: invDebit,
          description: 'Inventory',
        ),
        if (ppnIn != null)
          JournalLineInput(
            accountId: ppnIn.id,
            debitMinor: ppnMinor,
            description: 'PPN input',
          ),
        JournalLineInput(
          accountId: ap.id,
          creditMinor: totalMinor,
          description: 'Accounts payable',
        ),
      ],
    );
  }

  /// Customer receipt against AR: Dr Cash/Bank · Cr Accounts Receivable.
  Future<void> postReceiptJournal({
    required String refId,
    required int date,
    required int amountMinor,
    String method = 'cash',
  }) async {
    if (amountMinor <= 0) return;
    final into = await accountByCode(
      method == 'cash' ? AccountCode.cash : AccountCode.bank,
    );
    final ar = await accountByCode(AccountCode.receivable);
    if (into == null || ar == null) return;
    await postJournal(
      date: date,
      source: 'payment',
      refType: 'customer_receipt',
      refId: refId,
      memo: 'Customer receipt',
      lines: [
        JournalLineInput(
          accountId: into.id,
          debitMinor: amountMinor,
          description: 'Cash received',
        ),
        JournalLineInput(
          accountId: ar.id,
          creditMinor: amountMinor,
          description: 'Accounts receivable',
        ),
      ],
    );
  }

  /// Payment to a supplier against AP: Dr Accounts Payable · Cr Cash/Bank.
  Future<void> postSupplierPaymentJournal({
    required String refId,
    required int date,
    required int amountMinor,
    String method = 'cash',
  }) async {
    if (amountMinor <= 0) return;
    final ap = await accountByCode(AccountCode.accountsPayable);
    final from = await accountByCode(
      method == 'cash' ? AccountCode.cash : AccountCode.bank,
    );
    if (ap == null || from == null) return;
    await postJournal(
      date: date,
      source: 'payment',
      refType: 'supplier_payment',
      refId: refId,
      memo: 'Supplier payment',
      lines: [
        JournalLineInput(
          accountId: ap.id,
          debitMinor: amountMinor,
          description: 'Accounts payable',
        ),
        JournalLineInput(
          accountId: from.id,
          creditMinor: amountMinor,
          description: 'Cash paid',
        ),
      ],
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

  /// Invoices with goods-line detail for the CoreTax XML export: each completed
  /// sale in the period becomes one TaxInvoice; each sale line one GoodService
  /// (line DPP = line total − line PPN, both stored at sale time).
  Future<List<FakturXmlInvoice>> fakturXmlInvoicesForPeriod({
    int? fromMs,
    int? toMs,
  }) async {
    final sales = await salesForTaxPeriod(fromMs: fromMs, toMs: toMs);
    final out = <FakturXmlInvoice>[];
    for (final s in sales) {
      final lines = await (db.select(
        db.saleLines,
      )..where((t) => t.saleId.equals(s.id) & t.deletedAt.isNull())).get();
      out.add(
        FakturXmlInvoice(
          dateMs: s.createdAt,
          refNumber: s.number,
          buyerName: s.buyerName,
          buyerNpwp: s.buyerNpwp,
          lines: [
            for (final l in lines)
              FakturXmlLine(
                name: l.description,
                qty: l.qty,
                unitPriceMinor: l.unitPriceMinor,
                dppMinor: l.lineTotalMinor - l.taxMinor,
                ppnMinor: l.taxMinor,
              ),
          ],
        ),
      );
    }
    return out;
  }

  // --- Financial statements ---

  /// Sum of journal-line debits/credits per account (filtered by account type
  /// and an optional journal-date window), joined to account code/name/type.
  Future<List<({String code, String name, String type, int debit, int credit})>>
  _accountTotals({required List<String> types, int? fromMs, int? toMs}) async {
    final jl = db.journalLines;
    final j = db.journals;
    final a = db.accounts;
    final debit = jl.debitMinor.sum();
    final credit = jl.creditMinor.sum();

    var predicate =
        jl.deletedAt.isNull() &
        j.deletedAt.isNull() &
        a.deletedAt.isNull() &
        a.type.isIn(types);
    if (fromMs != null) {
      predicate = predicate & j.date.isBiggerOrEqualValue(fromMs);
    }
    if (toMs != null) {
      predicate = predicate & j.date.isSmallerThanValue(toMs);
    }

    final statement =
        db.select(jl).join([
            innerJoin(j, j.id.equalsExp(jl.journalId)),
            innerJoin(a, a.id.equalsExp(jl.accountId)),
          ])
          ..addColumns([debit, credit])
          ..where(predicate)
          ..groupBy([a.id])
          ..orderBy([OrderingTerm.asc(a.code)]);

    final rows = await statement.get();
    return [
      for (final r in rows)
        (
          code: r.readTable(a).code,
          name: r.readTable(a).name,
          type: r.readTable(a).type,
          debit: r.read(debit) ?? 0,
          credit: r.read(credit) ?? 0,
        ),
    ];
  }

  /// Profit & Loss for a period.
  Future<ProfitAndLoss> profitAndLoss({int? fromMs, int? toMs}) async {
    final rows = await _accountTotals(
      types: const ['income', 'expense'],
      fromMs: fromMs,
      toMs: toMs,
    );
    final income = <StatementLine>[];
    final expense = <StatementLine>[];
    var totalIncome = 0;
    var totalExpense = 0;
    for (final r in rows) {
      if (r.type == 'income') {
        final amount = r.credit - r.debit;
        income.add(
          StatementLine(code: r.code, name: r.name, amount: Money(amount)),
        );
        totalIncome += amount;
      } else {
        final amount = r.debit - r.credit;
        expense.add(
          StatementLine(code: r.code, name: r.name, amount: Money(amount)),
        );
        totalExpense += amount;
      }
    }
    return ProfitAndLoss(
      income: income,
      expense: expense,
      totalIncome: Money(totalIncome),
      totalExpense: Money(totalExpense),
    );
  }

  /// Balance sheet as of [asOfMs] (exclusive); null = all time.
  Future<BalanceSheet> balanceSheet({int? asOfMs}) async {
    final rows = await _accountTotals(
      types: const ['asset', 'liability', 'equity'],
      toMs: asOfMs,
    );
    final assets = <StatementLine>[];
    final liabilities = <StatementLine>[];
    final equity = <StatementLine>[];
    var totalAssets = 0;
    var totalLiabilities = 0;
    var totalEquity = 0;
    for (final r in rows) {
      if (r.type == 'asset') {
        final amount = r.debit - r.credit;
        assets.add(
          StatementLine(code: r.code, name: r.name, amount: Money(amount)),
        );
        totalAssets += amount;
      } else if (r.type == 'liability') {
        final amount = r.credit - r.debit;
        liabilities.add(
          StatementLine(code: r.code, name: r.name, amount: Money(amount)),
        );
        totalLiabilities += amount;
      } else {
        final amount = r.credit - r.debit;
        equity.add(
          StatementLine(code: r.code, name: r.name, amount: Money(amount)),
        );
        totalEquity += amount;
      }
    }

    // Retained earnings = net income to date (income - expense), folded into equity.
    final ie = await _accountTotals(
      types: const ['income', 'expense'],
      toMs: asOfMs,
    );
    var retained = 0;
    for (final r in ie) {
      retained += r.type == 'income'
          ? (r.credit - r.debit)
          : -(r.debit - r.credit);
    }
    equity.add(
      StatementLine(
        code: '',
        name: 'Retained earnings',
        amount: Money(retained),
      ),
    );
    totalEquity += retained;

    return BalanceSheet(
      assets: assets,
      liabilities: liabilities,
      equity: equity,
      totalAssets: Money(totalAssets),
      totalLiabilities: Money(totalLiabilities),
      totalEquity: Money(totalEquity),
      retainedEarnings: Money(retained),
    );
  }
}
