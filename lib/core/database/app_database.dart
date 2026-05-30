import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'tables/accounting_tables.dart';
import 'tables/catalog_tables.dart';
import 'tables/customers_tables.dart';
import 'tables/inventory_tables.dart';
import 'tables/ledger_tables.dart';
import 'tables/purchasing_tables.dart';
import 'tables/sales_tables.dart';
import 'tables/settings_tables.dart';
import 'tables/sync_tables.dart';

part 'app_database.g.dart';

/// The single application database. Tables are declared here and split across
/// `tables/` by concern; feature DAOs are layered on top in their data layers.
@DriftDatabase(
  tables: [
    // Infrastructure
    CompanySettings,
    Devices,
    ChangeLog,
    AppliedChanges,
    SyncMeta,
    // Catalog
    Brands,
    Categories,
    Products,
    ProductVariants,
    // Automotive catalog
    Vehicles,
    Fitments,
    CrossReferences,
    Supersessions,
    // Inventory
    Locations,
    StockMovements,
    // Sales
    Sales,
    SaleLines,
    Payments,
    // Accounting
    Accounts,
    TaxRates,
    Journals,
    JournalLines,
    // Customers
    Customers,
    CustomerVehicles,
    // Purchasing
    Suppliers,
    PurchaseOrders,
    PurchaseOrderLines,
    // Settlement ledger
    CustomerReceipts,
    SupplierPayments,
  ],
)
class AppDatabase extends _$AppDatabase {
  /// Pass an executor for tests (e.g. `NativeDatabase.memory()`); omit in the
  /// app to open the on-disk database under the OS app-support directory.
  AppDatabase([QueryExecutor? executor]) : super(executor ?? _openOnDisk());

  @override
  int get schemaVersion => 9;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) async {
      await m.createAll();
    },
    onUpgrade: (m, from, to) async {
      // v1 -> v2: catalog tables.
      if (from < 2) {
        await m.createTable(brands);
        await m.createTable(categories);
        await m.createTable(products);
        await m.createTable(productVariants);
      }
      // v2 -> v3: automotive catalog tables.
      if (from < 3) {
        await m.createTable(vehicles);
        await m.createTable(fitments);
        await m.createTable(crossReferences);
        await m.createTable(supersessions);
      }
      // v3 -> v4: inventory tables.
      if (from < 4) {
        await m.createTable(locations);
        await m.createTable(stockMovements);
      }
      // v4 -> v5: sales tables.
      if (from < 5) {
        await m.createTable(sales);
        await m.createTable(saleLines);
        await m.createTable(payments);
      }
      // v5 -> v6: accounting + tax/faktur fields.
      if (from < 6) {
        await m.createTable(accounts);
        await m.createTable(taxRates);
        await m.createTable(journals);
        await m.createTable(journalLines);
        // company_settings predates v6, so always add the new columns.
        await m.addColumn(companySettings, companySettings.isPkp);
        await m.addColumn(companySettings, companySettings.taxInclusive);
        await m.addColumn(companySettings, companySettings.defaultTaxRateId);
        // The `sales` table only pre-exists (without these columns) when
        // upgrading from v5; for from < 5 it was just created with the current
        // schema (which already includes them), so don't re-add.
        if (from >= 5) {
          await m.addColumn(sales, sales.buyerName);
          await m.addColumn(sales, sales.buyerNpwp);
          await m.addColumn(sales, sales.fakturNumber);
        }
      }
      // v6 -> v7: customers.
      if (from < 7) {
        await m.createTable(customers);
        await m.createTable(customerVehicles);
      }
      // v7 -> v8: purchasing.
      if (from < 8) {
        await m.createTable(suppliers);
        await m.createTable(purchaseOrders);
        await m.createTable(purchaseOrderLines);
      }
      // v8 -> v9: settlement ledger (AR receipts, AP payments).
      if (from < 9) {
        await m.createTable(customerReceipts);
        await m.createTable(supplierPayments);
      }
    },
    beforeOpen: (details) async {
      await customStatement('PRAGMA foreign_keys = ON');
    },
  );

  static QueryExecutor _openOnDisk() {
    return LazyDatabase(() async {
      final supportDir = await getApplicationSupportDirectory();
      final dbFolder = Directory(p.join(supportDir.path, 'Mine32 POS'));
      if (!dbFolder.existsSync()) {
        dbFolder.createSync(recursive: true);
      }
      final file = File(p.join(dbFolder.path, 'mine32.sqlite'));
      return NativeDatabase.createInBackground(file);
    });
  }
}
