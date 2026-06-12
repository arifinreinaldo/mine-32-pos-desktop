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
import 'package:mine32_pos/features/sales/data/returns_repository.dart';
import 'package:mine32_pos/features/sales/data/sales_repository.dart';
import 'package:mine32_pos/features/sales/domain/cart.dart';

class _Harness {
  final AppDatabase db;
  final CatalogRepository catalog;
  final InventoryRepository inventory;
  final AccountingRepository accounting;
  final SalesRepository sales;
  final ReturnsRepository returns;
  _Harness(
    this.db,
    this.catalog,
    this.inventory,
    this.accounting,
    this.sales,
    this.returns,
  );

  static Future<_Harness> create() async {
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
    final inventory = InventoryRepository(
      db: db,
      changeLog: changeLog,
      hlcService: hlc,
      clock: clock,
    );
    final catalog = CatalogRepository(
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
    final returns = ReturnsRepository(
      db: db,
      changeLog: changeLog,
      hlcService: hlc,
      clock: clock,
      inventory: inventory,
      accounting: accounting,
    );
    return _Harness(db, catalog, inventory, accounting, sales, returns);
  }
}

void main() {
  test('a full return restocks goods and reverses the sale journal', () async {
    final h = await _Harness.create();
    final variantId = await h.catalog.savePart(
      const PartDraft(
        name: 'Brake Pad',
        sku: 'BP-1',
        price: Money(11100),
        cost: Money(6000),
        coreCharge: Money(0),
      ),
    );
    await h.inventory.addMovement(
      variantId: variantId,
      locationId: 'L1',
      qty: 10,
      reason: MovementReason.purchase,
    );
    final sale = await h.sales.completeSale(
      lines: [
        CartLine(
          variantId: variantId,
          sku: 'BP-1',
          name: 'Brake Pad',
          unitPrice: const Money(11100),
          unitCost: const Money(6000),
          qty: 2,
        ),
      ],
      locationId: 'L1',
      tendered: const Money(22200),
      taxBasisPoints: 1100,
    );
    // 10 - 2 sold = 8 on hand.
    expect(await h.inventory.onHand(variantId, 'L1'), 8);

    final lineId = (await h.returns.returnableLines(
      sale.saleId,
    )).single.line.id;
    final result = await h.returns.createReturn(
      saleId: sale.saleId,
      quantitiesBySaleLineId: {lineId: 2},
      refundMethod: 'cash',
    );
    expect(result.number, 'CR-000001');
    expect(result.total, const Money(22200));

    // Goods are back in stock.
    expect(await h.inventory.onHand(variantId, 'L1'), 10);
    // Nothing left to return.
    expect(await h.returns.returnableLines(sale.saleId), isEmpty);
    expect(await h.returns.returnsForSale(sale.saleId), hasLength(1));

    // The sale + return net to zero across the affected accounts.
    final tb = await h.accounting.watchTrialBalance().first;
    Money bal(String code) => tb.firstWhere((r) => r.code == code).balance;
    expect(bal(AccountCode.cash), const Money(0));
    expect(bal(AccountCode.salesRevenue), const Money(0));
    expect(bal(AccountCode.ppnOutput), const Money(0));
    expect(bal(AccountCode.cogs), const Money(0));
    expect(bal(AccountCode.inventory), const Money(0));

    await h.db.close();
  });

  test('a partial return refunds and restocks a fraction', () async {
    final h = await _Harness.create();
    final variantId = await h.catalog.savePart(
      const PartDraft(
        name: 'Oil Filter',
        sku: 'OF-1',
        price: Money(11100),
        cost: Money(4000),
        coreCharge: Money(0),
      ),
    );
    await h.inventory.addMovement(
      variantId: variantId,
      locationId: 'L1',
      qty: 10,
      reason: MovementReason.purchase,
    );
    final sale = await h.sales.completeSale(
      lines: [
        CartLine(
          variantId: variantId,
          sku: 'OF-1',
          name: 'Oil Filter',
          unitPrice: const Money(11100),
          unitCost: const Money(4000),
          qty: 4,
        ),
      ],
      locationId: 'L1',
      tendered: const Money(44400),
      taxBasisPoints: 1100,
    );

    final lineId = (await h.returns.returnableLines(
      sale.saleId,
    )).single.line.id;
    final result = await h.returns.createReturn(
      saleId: sale.saleId,
      quantitiesBySaleLineId: {lineId: 1},
    );
    // One of four lines refunded: a quarter of 44400.
    expect(result.total, const Money(11100));
    // 10 - 4 + 1 = 7 on hand.
    expect(await h.inventory.onHand(variantId, 'L1'), 7);
    // 3 still returnable.
    expect((await h.returns.returnableLines(sale.saleId)).single.remaining, 3);

    await h.db.close();
  });

  test('voidSale returns everything to the original tender, once', () async {
    final h = await _Harness.create();
    final variantId = await h.catalog.savePart(
      const PartDraft(
        name: 'Clutch Kit',
        sku: 'CK-1',
        price: Money(11100),
        cost: Money(7000),
        coreCharge: Money(0),
      ),
    );
    await h.inventory.addMovement(
      variantId: variantId,
      locationId: 'L1',
      qty: 5,
      reason: MovementReason.purchase,
    );
    final sale = await h.sales.completeSale(
      lines: [
        CartLine(
          variantId: variantId,
          sku: 'CK-1',
          name: 'Clutch Kit',
          unitPrice: const Money(11100),
          unitCost: const Money(7000),
          qty: 3,
        ),
      ],
      locationId: 'L1',
      tendered: const Money(33300),
      taxBasisPoints: 1100,
      method: 'card', // non-cash → refund posts against Bank
    );
    expect(await h.inventory.onHand(variantId, 'L1'), 2);

    final result = await h.returns.voidSale(sale.saleId);
    expect(result.total, const Money(33300));

    // Stock fully restored; books net to zero on the bank side too.
    expect(await h.inventory.onHand(variantId, 'L1'), 5);
    final tb = await h.accounting.watchTrialBalance().first;
    Money bal(String code) => tb.firstWhere((r) => r.code == code).balance;
    expect(bal(AccountCode.bank), const Money(0));
    expect(bal(AccountCode.salesRevenue), const Money(0));
    expect(bal(AccountCode.inventory), const Money(0));

    // The return is tagged as a void and a second void is rejected.
    final returns = await h.returns.returnsForSale(sale.saleId);
    expect(returns.single.reason, 'void');
    await expectLater(h.returns.voidSale(sale.saleId), throwsStateError);

    await h.db.close();
  });

  test('returning more than remaining throws', () async {
    final h = await _Harness.create();
    final variantId = await h.catalog.savePart(
      const PartDraft(
        name: 'Spark Plug',
        sku: 'SP-1',
        price: Money(10000),
        cost: Money(5000),
        coreCharge: Money(0),
      ),
    );
    await h.inventory.addMovement(
      variantId: variantId,
      locationId: 'L1',
      qty: 5,
      reason: MovementReason.purchase,
    );
    final sale = await h.sales.completeSale(
      lines: [
        CartLine(
          variantId: variantId,
          sku: 'SP-1',
          name: 'Spark Plug',
          unitPrice: const Money(10000),
          unitCost: const Money(5000),
          qty: 1,
        ),
      ],
      locationId: 'L1',
      tendered: const Money(10000),
    );
    final lineId = (await h.returns.returnableLines(
      sale.saleId,
    )).single.line.id;
    await expectLater(
      h.returns.createReturn(
        saleId: sale.saleId,
        quantitiesBySaleLineId: {lineId: 2},
      ),
      throwsStateError,
    );
    await h.db.close();
  });
}
