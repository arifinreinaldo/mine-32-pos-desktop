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
import 'package:mine32_pos/features/catalog/data/catalog_repository.dart';
import 'package:mine32_pos/features/catalog/data/catalog_sync.dart';
import 'package:mine32_pos/features/catalog/domain/part_draft.dart';
import 'package:mine32_pos/features/inventory/data/inventory_repository.dart';
import 'package:mine32_pos/features/inventory/data/inventory_sync.dart';
import 'package:mine32_pos/features/inventory/domain/movement_reason.dart';
import 'package:mine32_pos/features/sales/data/sales_repository.dart';
import 'package:mine32_pos/features/sales/data/sales_sync.dart';
import 'package:mine32_pos/features/sales/domain/cart.dart';

class PosNode {
  final AppDatabase db;
  final SyncEngine engine;
  final CatalogRepository catalog;
  final InventoryRepository inventory;
  final SalesRepository sales;
  PosNode._(this.db, this.engine, this.catalog, this.inventory, this.sales);

  static Future<PosNode> create(
    String deviceId,
    InMemoryFolder folder,
    int startMillis,
  ) async {
    final db = AppDatabase(NativeDatabase.memory());
    final clock = MutableClock(startMillis);
    final hlc = HlcService(db, clock, deviceId);
    await hlc.load();
    final changeLog = ChangeLogWriter(db, deviceId);
    final registry = SyncRegistry();
    registerCoreSyncEntities(registry);
    registerCatalogSyncEntities(registry);
    registerInventorySyncEntities(registry);
    registerSalesSyncEntities(registry);
    final engine = SyncEngine(
      db: db,
      hlc: hlc,
      registry: registry,
      transport: InMemoryTransport(folder, deviceId),
      deviceId: deviceId,
    );
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
    );
    return PosNode._(db, engine, catalog, inventory, sales);
  }

  Future<void> close() => db.close();
}

void main() {
  group('SalesRepository.completeSale', () {
    test('persists sale + payment and decrements stock', () async {
      final n = await PosNode.create('solo', InMemoryFolder(), 1000);
      final variantId = await n.catalog.savePart(
        const PartDraft(
          name: 'Brake Pad',
          sku: 'BP-1',
          price: Money(2500),
          cost: Money(1500),
          coreCharge: Money(0),
        ),
      );
      const loc = 'L1';
      await n.inventory.addMovement(
        variantId: variantId,
        locationId: loc,
        qty: 10,
        reason: MovementReason.purchase,
      );

      final result = await n.sales.completeSale(
        lines: [
          CartLine(
            variantId: variantId,
            sku: 'BP-1',
            name: 'Brake Pad',
            unitPrice: const Money(2500),
            unitCost: const Money(1500),
            qty: 3,
          ),
        ],
        locationId: loc,
        tendered: const Money(10000),
      );

      expect(result.number, 'S-000001');
      expect(result.total, const Money(7500));
      expect(result.change, const Money(2500));
      expect(await n.inventory.onHand(variantId, loc), 7);

      final recent = await n.sales.watchRecentSales().first;
      expect(recent.length, 1);
      expect(recent.first.totalMinor, 7500);
      expect((await n.sales.linesForSale(result.saleId)).length, 1);

      await n.close();
    });

    test('sale numbers increment per device', () async {
      final n = await PosNode.create('solo', InMemoryFolder(), 1000);
      final v = await n.catalog.savePart(
        const PartDraft(
          name: 'X',
          sku: 'X',
          price: Money(100),
          cost: Money(50),
          coreCharge: Money(0),
        ),
      );
      final line = CartLine(
        variantId: v,
        sku: 'X',
        name: 'X',
        unitPrice: const Money(100),
        unitCost: const Money(50),
      );
      final a = await n.sales.completeSale(
        lines: [line],
        locationId: 'L1',
        tendered: const Money(100),
      );
      final b = await n.sales.completeSale(
        lines: [line],
        locationId: 'L1',
        tendered: const Money(100),
      );
      expect(a.number, 'S-000001');
      expect(b.number, 'S-000002');
      await n.close();
    });

    test('a sale and its stock impact replicate to another device', () async {
      final folder = InMemoryFolder();
      final a = await PosNode.create('device-a', folder, 1000);
      final b = await PosNode.create('device-b', folder, 1000);

      final variantId = await a.catalog.savePart(
        const PartDraft(
          name: 'Filter',
          sku: 'F-1',
          price: Money(900),
          cost: Money(400),
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
            sku: 'F-1',
            name: 'Filter',
            unitPrice: const Money(900),
            unitCost: const Money(400),
            qty: 4,
          ),
        ],
        locationId: 'L1',
        tendered: const Money(1000),
      );

      await a.engine.sync();
      await b.engine.sync();

      expect((await b.sales.watchRecentSales().first).length, 1);
      expect(await b.inventory.onHand(variantId, 'L1'), 6);

      await a.close();
      await b.close();
    });
  });
}
