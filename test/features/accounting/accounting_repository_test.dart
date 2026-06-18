import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mine32_pos/core/database/app_database.dart';
import 'package:mine32_pos/core/money/money.dart';
import 'package:mine32_pos/core/sync/change_log_writer.dart';
import 'package:mine32_pos/core/sync/hlc_service.dart';
import 'package:mine32_pos/core/time/clock.dart';
import 'package:mine32_pos/features/accounting/data/accounting_repository.dart';
import 'package:mine32_pos/features/accounting/domain/accounting_models.dart';
import 'package:mine32_pos/features/catalog/data/catalog_repository.dart';
import 'package:mine32_pos/features/catalog/domain/part_draft.dart';
import 'package:mine32_pos/features/inventory/data/inventory_repository.dart';
import 'package:mine32_pos/features/inventory/domain/movement_reason.dart';
import 'package:mine32_pos/features/sales/data/sales_repository.dart';
import 'package:mine32_pos/features/sales/domain/cart.dart';

AccountingRepository _acct(AppDatabase db) {
  final clock = MutableClock(1000);
  final hlc = HlcService(db, clock, 'dev');
  final changeLog = ChangeLogWriter(db, 'dev');
  return AccountingRepository(
    db: db,
    changeLog: changeLog,
    hlcService: hlc,
    clock: clock,
  );
}

void main() {
  group('AccountingRepository', () {
    test(
      'seedDefaults seeds a chart of accounts + PPN rate, idempotently',
      () async {
        final db = AppDatabase(NativeDatabase.memory());
        final repo = _acct(db);
        await repo.hlcService.load();
        await repo.seedDefaults();
        await repo.seedDefaults(); // idempotent

        expect((await db.select(db.accounts).get()).length, 11);
        expect((await db.select(db.taxRates).get()).length, 1);
        final rate = await repo.defaultTaxRate();
        expect(rate!.basisPoints, 1100);
        expect(rate.inclusive, isTrue);
        expect(await repo.accountByCode(AccountCode.cash), isNotNull);
        await db.close();
      },
    );

    test(
      'seedChartOfAccounts back-fills a missing account (upgrade self-heal)',
      () async {
        final db = AppDatabase(NativeDatabase.memory());
        final repo = _acct(db);
        await repo.hlcService.load();
        await repo.seedDefaults();
        expect((await db.select(db.accounts).get()).length, 11);

        // Simulate an older DB that predates the PPN Input account.
        await (db.delete(
          db.accounts,
        )..where((t) => t.code.equals(AccountCode.ppnInput))).go();
        expect((await db.select(db.accounts).get()).length, 10);
        expect(await repo.accountByCode(AccountCode.ppnInput), isNull);

        // Re-seeding adds only the missing one back.
        await repo.seedChartOfAccounts();
        expect((await db.select(db.accounts).get()).length, 11);
        expect(await repo.accountByCode(AccountCode.ppnInput), isNotNull);
        await db.close();
      },
    );

    test('postJournal rejects an unbalanced journal', () async {
      final db = AppDatabase(NativeDatabase.memory());
      final repo = _acct(db);
      await repo.hlcService.load();
      await repo.seedDefaults();
      final cash = (await repo.accountByCode(AccountCode.cash))!;
      await expectLater(
        repo.postJournal(
          date: 1,
          source: 'manual',
          lines: [JournalLineInput(accountId: cash.id, debitMinor: 100)],
        ),
        throwsStateError,
      );
      await db.close();
    });

    test('postManualJournal lists in the browser with its legs', () async {
      final db = AppDatabase(NativeDatabase.memory());
      final repo = _acct(db);
      await repo.hlcService.load();
      await repo.seedDefaults();
      final cash = (await repo.accountByCode(AccountCode.cash))!;
      final equity = (await repo.accountByCode(AccountCode.ownerEquity))!;

      final id = await repo.postManualJournal(
        date: 5,
        memo: 'Opening cash',
        lines: [
          JournalLineInput(
            accountId: cash.id,
            debitMinor: 100000,
            description: 'Cash',
          ),
          JournalLineInput(accountId: equity.id, creditMinor: 100000),
        ],
      );

      final journals = await repo.watchJournals().first;
      final j = journals.firstWhere((x) => x.id == id);
      expect(j.source, 'manual');
      expect(j.memo, 'Opening cash');
      expect(j.total, const Money(100000));

      final lines = await repo.journalLines(id);
      expect(lines, hasLength(2));
      final cashLine = lines.firstWhere(
        (l) => l.accountCode == AccountCode.cash,
      );
      expect(cashLine.debit, const Money(100000));
      expect(cashLine.credit, const Money(0));

      // listAccounts returns the seeded accounts, ordered by code.
      final accounts = await repo.listAccounts();
      expect(accounts, hasLength(11));
      final codes = accounts.map((a) => a.code).toList();
      expect(codes, [...codes]..sort());

      await db.close();
    });

    test('postManualJournal rejects an unbalanced entry', () async {
      final db = AppDatabase(NativeDatabase.memory());
      final repo = _acct(db);
      await repo.hlcService.load();
      await repo.seedDefaults();
      final cash = (await repo.accountByCode(AccountCode.cash))!;
      final equity = (await repo.accountByCode(AccountCode.ownerEquity))!;
      await expectLater(
        repo.postManualJournal(
          date: 1,
          lines: [
            JournalLineInput(accountId: cash.id, debitMinor: 100),
            JournalLineInput(accountId: equity.id, creditMinor: 90),
          ],
        ),
        throwsStateError,
      );
      await db.close();
    });

    test('tax-rate CRUD: save, switch default, delete', () async {
      final db = AppDatabase(NativeDatabase.memory());
      final repo = _acct(db);
      await repo.hlcService.load();
      await repo.seedDefaults();

      // Seeded with a single default PPN 11%.
      var rates = await repo.watchTaxRates().first;
      expect(rates, hasLength(1));
      expect(rates.first.name, 'PPN 11%');
      expect(rates.first.isDefault, isTrue);
      final ppn11 = rates.first;

      // Add a new default rate; the old one loses the default flag.
      final id0 = await repo.saveTaxRate(
        name: 'PPN 0% (export)',
        basisPoints: 0,
        isDefault: true,
      );
      rates = await repo.watchTaxRates().first;
      expect(rates, hasLength(2));
      expect((await repo.defaultTaxRate())!.id, id0);
      expect(rates.firstWhere((r) => r.id == ppn11.id).isDefault, isFalse);

      // Edit keeps identity.
      await repo.saveTaxRate(
        id: ppn11.id,
        name: 'PPN 11% (standard)',
        basisPoints: 1100,
      );
      rates = await repo.watchTaxRates().first;
      expect(rates, hasLength(2));
      expect(
        rates.firstWhere((r) => r.id == ppn11.id).name,
        'PPN 11% (standard)',
      );

      // Delete tombstones.
      await repo.deleteTaxRate(ppn11.id);
      rates = await repo.watchTaxRates().first;
      expect(rates, hasLength(1));
      expect(rates.first.id, id0);

      await db.close();
    });

    test('postSaleJournal produces a balanced trial balance', () async {
      final db = AppDatabase(NativeDatabase.memory());
      final repo = _acct(db);
      await repo.hlcService.load();
      await repo.seedDefaults();

      await repo.postSaleJournal(
        saleId: 'sale-1',
        date: 1,
        method: 'cash',
        totalMinor: 11100,
        dppMinor: 10000,
        ppnMinor: 1100,
        cogsMinor: 6000,
      );

      final tb = await repo.watchTrialBalance().first;
      Money bal(String code) => tb.firstWhere((r) => r.code == code).balance;

      expect(bal(AccountCode.cash), const Money(11100));
      expect(bal(AccountCode.salesRevenue), const Money(-10000));
      expect(bal(AccountCode.ppnOutput), const Money(-1100));
      expect(bal(AccountCode.cogs), const Money(6000));
      expect(bal(AccountCode.inventory), const Money(-6000));

      final totalDebit = tb.fold(0, (s, r) => s + r.debit.minorUnits);
      final totalCredit = tb.fold(0, (s, r) => s + r.credit.minorUnits);
      expect(totalDebit, totalCredit);

      await db.close();
    });

    test('a sale with PPN posts a journal and feeds the tax summary', () async {
      final db = AppDatabase(NativeDatabase.memory());
      final clock = MutableClock(1000);
      final hlc = HlcService(db, clock, 'dev');
      await hlc.load();
      final changeLog = ChangeLogWriter(db, 'dev');
      final accounting = AccountingRepository(
        db: db,
        changeLog: changeLog,
        hlcService: hlc,
        clock: clock,
      );
      await accounting.seedDefaults();
      final catalog = CatalogRepository(
        db: db,
        changeLog: changeLog,
        hlcService: hlc,
        clock: clock,
      );
      final inventory = InventoryRepository(
        db: db,
        changeLog: changeLog,
        hlcService: hlc,
        clock: clock,
      );
      final sales = SalesRepository(
        db: db,
        changeLog: changeLog,
        hlcService: hlc,
        clock: clock,
        inventory: inventory,
        accounting: accounting,
      );

      final variantId = await catalog.savePart(
        const PartDraft(
          name: 'Brake Pad',
          sku: 'BP-1',
          price: Money(11100), // tax-inclusive price
          cost: Money(6000),
          coreCharge: Money(0),
        ),
      );
      await inventory.addMovement(
        variantId: variantId,
        locationId: 'L1',
        qty: 10,
        reason: MovementReason.purchase,
      );

      await sales.completeSale(
        lines: [
          CartLine(
            variantId: variantId,
            sku: 'BP-1',
            name: 'Brake Pad',
            unitPrice: const Money(11100),
            unitCost: const Money(6000),
          ),
        ],
        locationId: 'L1',
        tendered: const Money(11100),
        taxBasisPoints: 1100,
      );

      final summary = await accounting.taxSummary();
      expect(summary.salesCount, 1);
      expect(summary.dpp, const Money(10000));
      expect(summary.ppn, const Money(1100));
      expect(summary.grandTotal, const Money(11100));

      // The sale posted a balanced journal.
      final tb = await accounting.watchTrialBalance().first;
      final totalDebit = tb.fold(0, (s, r) => s + r.debit.minorUnits);
      final totalCredit = tb.fold(0, (s, r) => s + r.credit.minorUnits);
      expect(totalDebit, totalCredit);
      expect(totalDebit, greaterThan(0));

      await db.close();
    });

    test('P&L and balance sheet reflect a sale', () async {
      final db = AppDatabase(NativeDatabase.memory());
      final clock = MutableClock(1000);
      final hlc = HlcService(db, clock, 'dev');
      await hlc.load();
      final changeLog = ChangeLogWriter(db, 'dev');
      final accounting = AccountingRepository(
        db: db,
        changeLog: changeLog,
        hlcService: hlc,
        clock: clock,
      );
      await accounting.seedDefaults();
      final catalog = CatalogRepository(
        db: db,
        changeLog: changeLog,
        hlcService: hlc,
        clock: clock,
      );
      final inventory = InventoryRepository(
        db: db,
        changeLog: changeLog,
        hlcService: hlc,
        clock: clock,
      );
      final sales = SalesRepository(
        db: db,
        changeLog: changeLog,
        hlcService: hlc,
        clock: clock,
        inventory: inventory,
        accounting: accounting,
      );
      final variantId = await catalog.savePart(
        const PartDraft(
          name: 'Brake Pad',
          sku: 'BP-1',
          price: Money(11100),
          cost: Money(6000),
          coreCharge: Money(0),
        ),
      );
      await inventory.addMovement(
        variantId: variantId,
        locationId: 'L1',
        qty: 10,
        reason: MovementReason.purchase,
      );
      await sales.completeSale(
        lines: [
          CartLine(
            variantId: variantId,
            sku: 'BP-1',
            name: 'Brake Pad',
            unitPrice: const Money(11100),
            unitCost: const Money(6000),
          ),
        ],
        locationId: 'L1',
        tendered: const Money(11100),
        taxBasisPoints: 1100,
      );

      final pl = await accounting.profitAndLoss();
      expect(pl.totalIncome, const Money(10000)); // sales DPP
      expect(pl.totalExpense, const Money(6000)); // COGS
      expect(pl.netProfit, const Money(4000));

      final bs = await accounting.balanceSheet();
      expect(bs.balanced, isTrue); // assets == liabilities + equity
      expect(bs.retainedEarnings, const Money(4000));

      await db.close();
    });
  });
}
