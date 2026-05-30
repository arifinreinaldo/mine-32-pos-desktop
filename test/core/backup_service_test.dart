import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mine32_pos/core/backup/backup_service.dart';
import 'package:mine32_pos/core/database/app_database.dart';
import 'package:mine32_pos/core/di/app_services.dart';
import 'package:mine32_pos/core/money/money.dart';
import 'package:mine32_pos/core/time/clock.dart';
import 'package:mine32_pos/features/accounting/data/accounting_repository.dart';
import 'package:mine32_pos/features/catalog/data/catalog_repository.dart';
import 'package:mine32_pos/features/catalog/domain/part_draft.dart';
import 'package:mine32_pos/features/customers/data/customers_repository.dart';
import 'package:mine32_pos/features/customers/domain/customer_draft.dart';
import 'package:mine32_pos/features/inventory/data/inventory_repository.dart';
import 'package:mine32_pos/features/inventory/domain/movement_reason.dart';
import 'package:mine32_pos/features/purchasing/data/purchasing_repository.dart';
import 'package:mine32_pos/features/purchasing/domain/purchasing_models.dart';
import 'package:mine32_pos/features/sales/data/sales_repository.dart';
import 'package:mine32_pos/features/sales/domain/cart.dart';

class _Kit {
  final AppServices services;
  final CatalogRepository catalog;
  final InventoryRepository inventory;
  final AccountingRepository accounting;
  final SalesRepository sales;
  final CustomersRepository customers;
  final PurchasingRepository purchasing;
  _Kit(
    this.services,
    this.catalog,
    this.inventory,
    this.accounting,
    this.sales,
    this.customers,
    this.purchasing,
  );

  BackupService get backup =>
      BackupService(db: services.db, registry: services.registry);

  static Future<_Kit> create() async {
    final services = await AppServices.initialize(
      database: AppDatabase(NativeDatabase.memory()),
      clock: MutableClock(1000),
    );
    final catalog = CatalogRepository(
      db: services.db,
      changeLog: services.changeLog,
      hlcService: services.hlc,
      clock: services.clock,
    );
    final inventory = InventoryRepository(
      db: services.db,
      changeLog: services.changeLog,
      hlcService: services.hlc,
      clock: services.clock,
    );
    final accounting = AccountingRepository(
      db: services.db,
      changeLog: services.changeLog,
      hlcService: services.hlc,
      clock: services.clock,
    );
    final sales = SalesRepository(
      db: services.db,
      changeLog: services.changeLog,
      hlcService: services.hlc,
      clock: services.clock,
      inventory: inventory,
      accounting: accounting,
    );
    final customers = CustomersRepository(
      db: services.db,
      changeLog: services.changeLog,
      hlcService: services.hlc,
      clock: services.clock,
      accounting: accounting,
    );
    final purchasing = PurchasingRepository(
      db: services.db,
      changeLog: services.changeLog,
      hlcService: services.hlc,
      clock: services.clock,
      inventory: inventory,
      accounting: accounting,
    );
    return _Kit(
      services,
      catalog,
      inventory,
      accounting,
      sales,
      customers,
      purchasing,
    );
  }
}

void main() {
  test('backup of one database restores fully into another', () async {
    final a = await _Kit.create();

    final variantId = await a.catalog.savePart(
      const PartDraft(
        name: 'Brake Pad',
        sku: 'BP-1',
        price: Money(11100),
        cost: Money(6000),
        coreCharge: Money(0),
      ),
    );
    await a.inventory.addMovement(
      variantId: variantId,
      locationId: 'L1',
      qty: 10,
      reason: MovementReason.purchase,
    );
    await a.sales.completeSale(
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
    await a.customers.saveCustomer(const CustomerDraft(name: 'Bengkel Maju'));
    await a.purchasing.saveSupplier(
      const SupplierDraft(name: 'PT Sumber Parts'),
    );

    final bytes = await a.backup.exportBytes();

    // Restore into a brand-new database.
    final b = await _Kit.create();
    final result = await b.backup.importBytes(bytes);
    expect(result.rows, greaterThan(0));

    // Catalog, stock, sale, customer and supplier all came across.
    final items = await b.catalog.watch().first;
    expect(items.map((i) => i.sku), contains('BP-1'));
    expect(await b.inventory.onHand(variantId, 'L1'), 8); // 10 - 2 sold
    expect((await b.sales.watchRecentSales().first), hasLength(1));
    expect((await b.customers.watch().first), hasLength(1));
    expect((await b.purchasing.watchSuppliers().first), hasLength(1));

    // The chart of accounts did NOT duplicate (deterministic seed ids), and the
    // restored journals keep the books balanced.
    final tb = await b.accounting.watchTrialBalance().first;
    expect(tb, hasLength(10));
    final totalDebit = tb.fold(0, (s, r) => s + r.debit.minorUnits);
    final totalCredit = tb.fold(0, (s, r) => s + r.credit.minorUnits);
    expect(totalDebit, totalCredit);
    expect(totalDebit, greaterThan(0));

    // Restoring again is idempotent: stock is not double-counted and the
    // catalog is not duplicated.
    await b.backup.importBytes(bytes);
    expect(await b.inventory.onHand(variantId, 'L1'), 8);
    expect((await b.catalog.watch().first), hasLength(1));
    expect((await b.accounting.watchTrialBalance().first), hasLength(10));

    await a.services.dispose();
    await b.services.dispose();
  });

  test('importBytes rejects a non-backup file', () async {
    final a = await _Kit.create();
    expect(
      () => a.backup.importBytes('not a backup'.codeUnits),
      throwsFormatException,
    );
    await a.services.dispose();
  });
}
