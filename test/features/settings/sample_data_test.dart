import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mine32_pos/core/database/app_database.dart';
import 'package:mine32_pos/core/sync/change_log_writer.dart';
import 'package:mine32_pos/core/sync/hlc_service.dart';
import 'package:mine32_pos/core/time/clock.dart';
import 'package:mine32_pos/features/accounting/data/accounting_repository.dart';
import 'package:mine32_pos/features/catalog/data/auto_parts_repository.dart';
import 'package:mine32_pos/features/catalog/data/catalog_repository.dart';
import 'package:mine32_pos/features/customers/data/customers_repository.dart';
import 'package:mine32_pos/features/inventory/data/inventory_repository.dart';
import 'package:mine32_pos/features/purchasing/data/purchasing_repository.dart';
import 'package:mine32_pos/features/settings/data/sample_data.dart';

void main() {
  test(
    'SampleData.load seeds parts, stock, supplier and customer (idempotent)',
    () async {
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
      final autoParts = AutoPartsRepository(
        db: db,
        changeLog: changeLog,
        hlcService: hlc,
        clock: clock,
      );
      final purchasing = PurchasingRepository(
        db: db,
        changeLog: changeLog,
        hlcService: hlc,
        clock: clock,
        inventory: inventory,
        accounting: accounting,
      );
      final customers = CustomersRepository(
        db: db,
        changeLog: changeLog,
        hlcService: hlc,
        clock: clock,
        accounting: accounting,
      );

      final count = await SampleData.load(
        catalog: catalog,
        inventory: inventory,
        autoParts: autoParts,
        purchasing: purchasing,
        customers: customers,
      );
      expect(count, 10);

      final items = await catalog.watch().first;
      expect(items.length, 10);
      final loc = (await inventory.watchLocations().first).first.id;
      final bp = items.firstWhere((i) => i.sku == 'BP-1001');
      expect(await inventory.onHand(bp.variantId, loc), 12);
      expect((await purchasing.watchSuppliers().first).length, 1);
      expect((await customers.watch().first).length, 1);

      // Lookup by interchange number finds the seeded cross-reference.
      final hits = await autoParts.lookupVariantIdsByNumber('90915-YZZE1');
      expect(hits, isNotEmpty);

      // Idempotent: running again is a no-op.
      final again = await SampleData.load(
        catalog: catalog,
        inventory: inventory,
        autoParts: autoParts,
        purchasing: purchasing,
        customers: customers,
      );
      expect(again, 0);
      expect((await catalog.watch().first).length, 10);

      await db.close();
    },
  );
}
