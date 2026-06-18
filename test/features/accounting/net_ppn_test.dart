import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mine32_pos/core/database/app_database.dart';
import 'package:mine32_pos/core/money/money.dart';
import 'package:mine32_pos/core/sync/change_log_writer.dart';
import 'package:mine32_pos/core/sync/hlc_service.dart';
import 'package:mine32_pos/core/time/clock.dart';
import 'package:mine32_pos/features/accounting/data/accounting_repository.dart';
import 'package:mine32_pos/features/catalog/data/catalog_repository.dart';
import 'package:mine32_pos/features/catalog/domain/part_draft.dart';
import 'package:mine32_pos/features/inventory/data/inventory_repository.dart';
import 'package:mine32_pos/features/purchasing/data/purchasing_repository.dart';
import 'package:mine32_pos/features/purchasing/domain/purchasing_models.dart';
import 'package:mine32_pos/features/sales/data/sales_repository.dart';
import 'package:mine32_pos/features/sales/domain/cart.dart';

void main() {
  test('netPpn = output PPN (sales) − input PPN (purchases)', () async {
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
    // Company is PKP so purchases split input PPN.
    await db
        .into(db.companySettings)
        .insert(
          CompanySettingsCompanion.insert(
            id: 'default',
            createdAt: 0,
            updatedAt: 0,
            updatedHlc: '0',
            isPkp: const Value(true),
          ),
        );
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
    final purchasing = PurchasingRepository(
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
        price: Money(22200),
        cost: Money(11100),
        coreCharge: Money(0),
      ),
    );
    final supplierId = await purchasing.saveSupplier(
      const SupplierDraft(name: 'PT Sumber Parts'),
    );

    // Buy 1 @ 11100 incl 11% → input PPN 1100.
    final poId = await purchasing.createPurchaseOrder(
      supplierId: supplierId,
      locationId: 'L1',
      lines: [
        PoLineInput(
          variantId: variantId,
          description: 'Brake Pad',
          qty: 1,
          unitCostMinor: 11100,
        ),
      ],
    );
    await purchasing.receivePurchaseOrder(poId);

    // Sell 1 @ 22200 incl 11% → output PPN 2200.
    await sales.completeSale(
      lines: [
        CartLine(
          variantId: variantId,
          sku: 'BP-1',
          name: 'Brake Pad',
          unitPrice: const Money(22200),
          unitCost: const Money(11100),
        ),
      ],
      locationId: 'L1',
      tendered: const Money(22200),
      taxBasisPoints: 1100,
    );

    final ppn = await accounting.netPpn();
    expect(ppn.output, const Money(2200));
    expect(ppn.input, const Money(1100));
    expect(
      ppn.payable,
      const Money(1100),
    ); // 2200 − 1100 owed to the tax office

    await db.close();
  });
}
