import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mine32_pos/core/database/app_database.dart';
import 'package:mine32_pos/core/money/money.dart';
import 'package:mine32_pos/core/sync/change_log_writer.dart';
import 'package:mine32_pos/core/sync/core_sync_entities.dart';
import 'package:mine32_pos/core/sync/hlc_service.dart';
import 'package:mine32_pos/core/sync/sync_engine.dart';
import 'package:mine32_pos/core/sync/sync_entity.dart';
import 'package:mine32_pos/core/sync/transport/in_memory_transport.dart';
import 'package:mine32_pos/core/time/clock.dart';
import 'package:mine32_pos/features/accounting/data/accounting_repository.dart';
import 'package:mine32_pos/features/accounting/domain/accounting_models.dart';
import 'package:mine32_pos/features/catalog/data/catalog_repository.dart';
import 'package:mine32_pos/features/catalog/domain/part_draft.dart';
import 'package:mine32_pos/features/inventory/data/inventory_repository.dart';
import 'package:mine32_pos/features/purchasing/data/purchasing_repository.dart';
import 'package:mine32_pos/features/purchasing/data/purchasing_sync.dart';
import 'package:mine32_pos/features/purchasing/domain/purchasing_models.dart';

class Node {
  final AppDatabase db;
  final SyncEngine engine;
  final CatalogRepository catalog;
  final InventoryRepository inventory;
  final AccountingRepository accounting;
  final PurchasingRepository purchasing;
  Node._(
    this.db,
    this.engine,
    this.catalog,
    this.inventory,
    this.accounting,
    this.purchasing,
  );

  static Future<Node> create(
    String deviceId,
    InMemoryFolder folder,
    int t,
  ) async {
    final db = AppDatabase(NativeDatabase.memory());
    final clock = MutableClock(t);
    final hlc = HlcService(db, clock, deviceId);
    await hlc.load();
    final changeLog = ChangeLogWriter(db, deviceId);
    final registry = SyncRegistry();
    registerCoreSyncEntities(registry);
    registerPurchasingSyncEntities(registry);
    final engine = SyncEngine(
      db: db,
      hlc: hlc,
      registry: registry,
      transport: InMemoryTransport(folder, deviceId),
      deviceId: deviceId,
    );
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
    final purchasing = PurchasingRepository(
      db: db,
      changeLog: changeLog,
      hlcService: hlc,
      clock: clock,
      inventory: inventory,
      accounting: accounting,
    );
    return Node._(db, engine, catalog, inventory, accounting, purchasing);
  }

  Future<void> close() => db.close();
}

void main() {
  group('PurchasingRepository', () {
    test('supplier save/search/delete + sync', () async {
      final folder = InMemoryFolder();
      final a = await Node.create('a', folder, 1000);
      final b = await Node.create('b', folder, 1000);
      final id = await a.purchasing.saveSupplier(
        const SupplierDraft(name: 'PT Sumber Parts', phone: '021-555'),
      );
      expect(
        (await a.purchasing.watchSuppliers(query: 'Sumber').first).length,
        1,
      );

      await a.engine.sync();
      await b.engine.sync();
      expect(
        (await b.purchasing.watchSuppliers().first).map((s) => s.name),
        contains('PT Sumber Parts'),
      );

      await a.purchasing.deleteSupplier(id);
      expect(await a.purchasing.watchSuppliers().first, isEmpty);

      await a.close();
      await b.close();
    });

    test('receiving a PO adds stock and posts Dr Inventory / Cr AP', () async {
      final n = await Node.create('solo', InMemoryFolder(), 1000);
      final supplierId = await n.purchasing.saveSupplier(
        const SupplierDraft(name: 'PT Sumber Parts'),
      );
      final variantId = await n.catalog.savePart(
        const PartDraft(
          name: 'Oil Filter',
          sku: 'OF-1',
          price: Money(900),
          cost: Money(500),
          coreCharge: Money(0),
        ),
      );

      final poId = await n.purchasing.createPurchaseOrder(
        supplierId: supplierId,
        locationId: 'L1',
        lines: [
          PoLineInput(
            variantId: variantId,
            description: 'Oil Filter',
            qty: 20,
            unitCostMinor: 30000,
          ),
        ],
      );

      expect(await n.inventory.onHand(variantId, 'L1'), 0);

      await n.purchasing.receivePurchaseOrder(poId);

      expect(await n.inventory.onHand(variantId, 'L1'), 20);
      expect(await n.purchasing.apBalance(supplierId), 600000);
      expect((await n.purchasing.getPurchaseOrder(poId))!.status, 'received');

      final tb = await n.accounting.watchTrialBalance().first;
      Money bal(String code) => tb.firstWhere((r) => r.code == code).balance;
      expect(bal(AccountCode.inventory), const Money(600000));
      expect(bal(AccountCode.accountsPayable), const Money(-600000));
      final totalDebit = tb.fold(0, (s, r) => s + r.debit.minorUnits);
      final totalCredit = tb.fold(0, (s, r) => s + r.credit.minorUnits);
      expect(totalDebit, totalCredit);

      // Receiving again is a no-op (no double stock).
      await n.purchasing.receivePurchaseOrder(poId);
      expect(await n.inventory.onHand(variantId, 'L1'), 20);

      await n.close();
    });

    test('a PKP company splits recoverable input-PPN on receipt', () async {
      final n = await Node.create('solo', InMemoryFolder(), 1000);
      // Mark the company VAT-registered; the default PPN 11% rate is seeded.
      await n.db
          .into(n.db.companySettings)
          .insert(
            CompanySettingsCompanion.insert(
              id: 'default',
              createdAt: 0,
              updatedAt: 0,
              updatedHlc: '0',
              isPkp: const Value(true),
            ),
          );
      final supplierId = await n.purchasing.saveSupplier(
        const SupplierDraft(name: 'PT Sumber Parts'),
      );
      final variantId = await n.catalog.savePart(
        const PartDraft(
          name: 'Oil Filter',
          sku: 'OF-1',
          price: Money(900),
          cost: Money(500),
          coreCharge: Money(0),
        ),
      );
      final poId = await n.purchasing.createPurchaseOrder(
        supplierId: supplierId,
        locationId: 'L1',
        lines: [
          PoLineInput(
            variantId: variantId,
            description: 'Oil Filter',
            qty: 1,
            unitCostMinor: 11100, // tax-inclusive
          ),
        ],
      );
      await n.purchasing.receivePurchaseOrder(poId);

      // 11100 incl 11% → DPP 10000 (Inventory) + input PPN 1100; AP gross 11100.
      final tb = await n.accounting.watchTrialBalance().first;
      Money bal(String code) => tb.firstWhere((r) => r.code == code).balance;
      expect(bal(AccountCode.inventory), const Money(10000));
      expect(bal(AccountCode.ppnInput), const Money(1100));
      expect(bal(AccountCode.accountsPayable), const Money(-11100));
      final td = tb.fold(0, (s, r) => s + r.debit.minorUnits);
      final tc = tb.fold(0, (s, r) => s + r.credit.minorUnits);
      expect(td, tc);
      // AP balance stays gross (what's owed to the supplier).
      expect(await n.purchasing.apBalance(supplierId), 11100);

      await n.close();
    });

    test(
      'partial receipt: stock, AP and incoming track the received part',
      () async {
        final n = await Node.create('solo', InMemoryFolder(), 1000);
        final supplierId = await n.purchasing.saveSupplier(
          const SupplierDraft(name: 'PT Sumber Parts'),
        );
        final variantId = await n.catalog.savePart(
          const PartDraft(
            name: 'Oil Filter',
            sku: 'OF-1',
            price: Money(900),
            cost: Money(500),
            coreCharge: Money(0),
          ),
        );
        final poId = await n.purchasing.createPurchaseOrder(
          supplierId: supplierId,
          locationId: 'L1',
          lines: [
            PoLineInput(
              variantId: variantId,
              description: 'Oil Filter',
              qty: 20,
              unitCostMinor: 30000,
            ),
          ],
        );
        final lineId = (await n.purchasing.linesForPo(poId)).single.id;

        // Receive 8 of 20.
        await n.purchasing.receiveLines(poId, {lineId: 8});
        expect((await n.purchasing.getPurchaseOrder(poId))!.status, 'partial');
        expect(await n.inventory.onHand(variantId, 'L1'), 8);
        expect(await n.purchasing.apBalance(supplierId), 8 * 30000);
        // 12 still on the way.
        expect(
          (await n.purchasing.watchIncomingByVariant().first)[variantId],
          12,
        );

        // Over-receiving is clamped to the remaining 12 → fully received.
        await n.purchasing.receiveLines(poId, {lineId: 999});
        expect((await n.purchasing.getPurchaseOrder(poId))!.status, 'received');
        expect(await n.inventory.onHand(variantId, 'L1'), 20);
        expect(await n.purchasing.apBalance(supplierId), 20 * 30000);
        expect(await n.purchasing.watchIncomingByVariant().first, isEmpty);

        // Books stay balanced across the two partial journals.
        final tb = await n.accounting.watchTrialBalance().first;
        final td = tb.fold(0, (s, r) => s + r.debit.minorUnits);
        final tc = tb.fold(0, (s, r) => s + r.credit.minorUnits);
        expect(td, tc);

        await n.close();
      },
    );

    test('a payment allocated to a PO clears that PO from open list', () async {
      final n = await Node.create('solo', InMemoryFolder(), 1000);
      final supplierId = await n.purchasing.saveSupplier(
        const SupplierDraft(name: 'PT Sumber Parts'),
      );
      final variantId = await n.catalog.savePart(
        const PartDraft(
          name: 'Oil Filter',
          sku: 'OF-1',
          price: Money(900),
          cost: Money(500),
          coreCharge: Money(0),
        ),
      );
      Future<String> orderAndReceive() async {
        final poId = await n.purchasing.createPurchaseOrder(
          supplierId: supplierId,
          locationId: 'L1',
          lines: [
            PoLineInput(
              variantId: variantId,
              description: 'Oil Filter',
              qty: 10,
              unitCostMinor: 30000,
            ),
          ],
        );
        await n.purchasing.receivePurchaseOrder(poId);
        return poId;
      }

      final firstPo = await orderAndReceive();
      await orderAndReceive();

      var open = await n.purchasing.openPurchaseOrders(supplierId);
      expect(open, hasLength(2));
      expect(open.every((o) => o.outstanding == 300000), isTrue);

      // Pay the first PO in full.
      await n.purchasing.paySupplier(
        supplierId: supplierId,
        amountMinor: 300000,
        poId: firstPo,
      );

      open = await n.purchasing.openPurchaseOrders(supplierId);
      expect(open, hasLength(1), reason: 'first PO settled');
      expect(open.single.po.id, isNot(firstPo));
      // Overall AP still nets (600000 received − 300000 paid).
      expect(await n.purchasing.apBalance(supplierId), 300000);

      await n.close();
    });

    test('incoming reflects open POs and clears once received', () async {
      final n = await Node.create('solo', InMemoryFolder(), 1000);
      final supplierId = await n.purchasing.saveSupplier(
        const SupplierDraft(name: 'PT Sumber Parts'),
      );
      final variantId = await n.catalog.savePart(
        const PartDraft(
          name: 'Oil Filter',
          sku: 'OF-1',
          price: Money(900),
          cost: Money(500),
          coreCharge: Money(0),
        ),
      );
      expect(await n.purchasing.watchIncomingByVariant().first, isEmpty);

      final poId = await n.purchasing.createPurchaseOrder(
        supplierId: supplierId,
        locationId: 'L1',
        lines: [
          PoLineInput(
            variantId: variantId,
            description: 'Oil Filter',
            qty: 20,
            unitCostMinor: 30000,
          ),
        ],
      );
      // 20 units on the way while the PO is open.
      expect(
        (await n.purchasing.watchIncomingByVariant().first)[variantId],
        20,
      );

      // Once received the goods are on-hand, so nothing is incoming.
      await n.purchasing.receivePurchaseOrder(poId);
      expect(await n.purchasing.watchIncomingByVariant().first, isEmpty);
      expect(await n.inventory.onHand(variantId, 'L1'), 20);

      await n.close();
    });

    test('paying a supplier reduces AP and posts Dr AP / Cr Cash', () async {
      final n = await Node.create('solo', InMemoryFolder(), 1000);
      final supplierId = await n.purchasing.saveSupplier(
        const SupplierDraft(name: 'PT Sumber Parts'),
      );
      final variantId = await n.catalog.savePart(
        const PartDraft(
          name: 'Oil Filter',
          sku: 'OF-1',
          price: Money(900),
          cost: Money(500),
          coreCharge: Money(0),
        ),
      );
      final poId = await n.purchasing.createPurchaseOrder(
        supplierId: supplierId,
        locationId: 'L1',
        lines: [
          PoLineInput(
            variantId: variantId,
            description: 'Oil Filter',
            qty: 20,
            unitCostMinor: 30000,
          ),
        ],
      );
      await n.purchasing.receivePurchaseOrder(poId);
      expect(await n.purchasing.apBalance(supplierId), 600000);

      await n.purchasing.paySupplier(
        supplierId: supplierId,
        amountMinor: 600000,
      );
      expect(await n.purchasing.apBalance(supplierId), 0);

      final tb = await n.accounting.watchTrialBalance().first;
      Money bal(String code) => tb.firstWhere((r) => r.code == code).balance;
      expect(bal(AccountCode.accountsPayable), const Money(0));
      expect(bal(AccountCode.cash), const Money(-600000));
      final totalDebit = tb.fold(0, (s, r) => s + r.debit.minorUnits);
      final totalCredit = tb.fold(0, (s, r) => s + r.credit.minorUnits);
      expect(totalDebit, totalCredit);

      await n.close();
    });
  });
}
