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
import 'package:mine32_pos/features/customers/data/customers_repository.dart';
import 'package:mine32_pos/features/customers/data/customers_sync.dart';
import 'package:mine32_pos/features/customers/domain/customer_draft.dart';
import 'package:mine32_pos/features/inventory/data/inventory_repository.dart';
import 'package:mine32_pos/features/inventory/domain/movement_reason.dart';
import 'package:mine32_pos/features/sales/data/sales_repository.dart';
import 'package:mine32_pos/features/sales/domain/cart.dart';

class Node {
  final AppDatabase db;
  final SyncEngine engine;
  final CustomersRepository customers;
  final CatalogRepository catalog;
  final InventoryRepository inventory;
  final AccountingRepository accounting;
  final SalesRepository sales;
  Node._(
    this.db,
    this.engine,
    this.customers,
    this.catalog,
    this.inventory,
    this.accounting,
    this.sales,
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
    registerCustomerSyncEntities(registry);
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
    return Node._(
      db,
      engine,
      CustomersRepository(
        db: db,
        changeLog: changeLog,
        hlcService: hlc,
        clock: clock,
        accounting: accounting,
      ),
      CatalogRepository(
        db: db,
        changeLog: changeLog,
        hlcService: hlc,
        clock: clock,
      ),
      inventory,
      accounting,
      SalesRepository(
        db: db,
        changeLog: changeLog,
        hlcService: hlc,
        clock: clock,
        inventory: inventory,
        accounting: accounting,
      ),
    );
  }

  Future<void> close() => db.close();
}

void main() {
  group('CustomersRepository', () {
    test('save, search, vehicles, delete', () async {
      final n = await Node.create('solo', InMemoryFolder(), 1000);
      final id = await n.customers.saveCustomer(
        const CustomerDraft(name: 'Budi Santoso', phone: '0812-1111'),
      );
      expect((await n.customers.watch().first).length, 1);
      expect((await n.customers.watch(query: 'Budi').first).length, 1);
      expect((await n.customers.watch(query: 'nobody').first), isEmpty);

      final vid = await n.customers.addVehicle(
        customerId: id,
        plate: 'B 1234 XY',
        description: 'Toyota Avanza',
      );
      expect((await n.customers.watchVehicles(id).first).length, 1);
      await n.customers.removeVehicle(vid);
      expect((await n.customers.watchVehicles(id).first), isEmpty);

      await n.customers.deleteCustomer(id);
      expect(await n.customers.watch().first, isEmpty);
      await n.close();
    });

    test(
      'an on-account sale raises the AR balance and debits Receivable',
      () async {
        final n = await Node.create('solo', InMemoryFolder(), 1000);
        final customerId = await n.customers.saveCustomer(
          const CustomerDraft(name: 'PT Bengkel Jaya'),
        );
        final variantId = await n.catalog.savePart(
          const PartDraft(
            name: 'Clutch Kit',
            sku: 'CK-1',
            price: Money(50000),
            cost: Money(30000),
            coreCharge: Money(0),
          ),
        );
        await n.inventory.addMovement(
          variantId: variantId,
          locationId: 'L1',
          qty: 10,
          reason: MovementReason.purchase,
        );

        await n.sales.completeSale(
          lines: [
            CartLine(
              variantId: variantId,
              sku: 'CK-1',
              name: 'Clutch Kit',
              unitPrice: const Money(50000),
              unitCost: const Money(30000),
            ),
          ],
          locationId: 'L1',
          tendered: const Money(0),
          customerId: customerId,
          onAccount: true,
        );

        expect(await n.customers.arBalance(customerId), 50000);

        final tb = await n.accounting.watchTrialBalance().first;
        final receivable = tb
            .firstWhere((r) => r.code == AccountCode.receivable)
            .balance;
        expect(
          receivable,
          const Money(50000),
          reason: 'Dr Accounts Receivable',
        );

        // Journal still balances.
        final totalDebit = tb.fold(0, (s, r) => s + r.debit.minorUnits);
        final totalCredit = tb.fold(0, (s, r) => s + r.credit.minorUnits);
        expect(totalDebit, totalCredit);
        await n.close();
      },
    );

    test('receiving a payment reduces AR and posts Dr Cash / Cr AR', () async {
      final n = await Node.create('solo', InMemoryFolder(), 1000);
      final customerId = await n.customers.saveCustomer(
        const CustomerDraft(name: 'PT Bengkel Jaya'),
      );
      final variantId = await n.catalog.savePart(
        const PartDraft(
          name: 'Clutch Kit',
          sku: 'CK-1',
          price: Money(50000),
          cost: Money(30000),
          coreCharge: Money(0),
        ),
      );
      await n.inventory.addMovement(
        variantId: variantId,
        locationId: 'L1',
        qty: 10,
        reason: MovementReason.purchase,
      );
      await n.sales.completeSale(
        lines: [
          CartLine(
            variantId: variantId,
            sku: 'CK-1',
            name: 'Clutch Kit',
            unitPrice: const Money(50000),
            unitCost: const Money(30000),
          ),
        ],
        locationId: 'L1',
        tendered: const Money(0),
        customerId: customerId,
        onAccount: true,
      );
      expect(await n.customers.arBalance(customerId), 50000);

      await n.customers.receivePayment(
        customerId: customerId,
        amountMinor: 20000,
      );
      expect(await n.customers.arBalance(customerId), 30000);

      final tb = await n.accounting.watchTrialBalance().first;
      Money bal(String code) => tb.firstWhere((r) => r.code == code).balance;
      expect(bal(AccountCode.receivable), const Money(30000));
      expect(bal(AccountCode.cash), const Money(20000));
      final totalDebit = tb.fold(0, (s, r) => s + r.debit.minorUnits);
      final totalCredit = tb.fold(0, (s, r) => s + r.credit.minorUnits);
      expect(totalDebit, totalCredit);
      await n.close();
    });

    test('a receipt allocated to an invoice clears that invoice', () async {
      final n = await Node.create('solo', InMemoryFolder(), 1000);
      final customerId = await n.customers.saveCustomer(
        const CustomerDraft(name: 'PT Bengkel Jaya'),
      );
      final variantId = await n.catalog.savePart(
        const PartDraft(
          name: 'Clutch Kit',
          sku: 'CK-1',
          price: Money(50000),
          cost: Money(30000),
          coreCharge: Money(0),
        ),
      );
      await n.inventory.addMovement(
        variantId: variantId,
        locationId: 'L1',
        qty: 10,
        reason: MovementReason.purchase,
      );
      // Two on-account sales → two open invoices.
      Future<String> sell() async => (await n.sales.completeSale(
        lines: [
          CartLine(
            variantId: variantId,
            sku: 'CK-1',
            name: 'Clutch Kit',
            unitPrice: const Money(50000),
            unitCost: const Money(30000),
          ),
        ],
        locationId: 'L1',
        tendered: const Money(0),
        customerId: customerId,
        onAccount: true,
      )).saleId;
      final firstId = await sell();
      await sell();

      var open = await n.customers.openInvoices(customerId);
      expect(open, hasLength(2));
      expect(open.every((i) => i.outstanding == 50000), isTrue);

      // Allocate a full payment to the first invoice.
      await n.customers.receivePayment(
        customerId: customerId,
        amountMinor: 50000,
        saleId: firstId,
      );

      open = await n.customers.openInvoices(customerId);
      expect(open, hasLength(1), reason: 'first invoice settled');
      expect(open.single.sale.id, isNot(firstId));
      // Overall AR still nets correctly (100000 billed − 50000 received).
      expect(await n.customers.arBalance(customerId), 50000);

      await n.close();
    });

    test('customers replicate to another device', () async {
      final folder = InMemoryFolder();
      final a = await Node.create('device-a', folder, 1000);
      final b = await Node.create('device-b', folder, 1000);
      await a.customers.saveCustomer(
        const CustomerDraft(name: 'Siti', phone: '0813-2222'),
      );
      await a.engine.sync();
      await b.engine.sync();
      final onB = await b.customers.watch().first;
      expect(onB.map((c) => c.name), contains('Siti'));
      await a.close();
      await b.close();
    });
  });
}
