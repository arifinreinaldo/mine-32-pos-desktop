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

        expect((await db.select(db.accounts).get()).length, 10);
        expect((await db.select(db.taxRates).get()).length, 1);
        final rate = await repo.defaultTaxRate();
        expect(rate!.basisPoints, 1100);
        expect(rate.inclusive, isTrue);
        expect(await repo.accountByCode(AccountCode.cash), isNotNull);
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
  });
}
