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

class CatalogNode {
  final String deviceId;
  final AppDatabase db;
  final MutableClock clock;
  final HlcService hlc;
  final SyncEngine engine;
  final CatalogRepository repo;

  CatalogNode._(
    this.deviceId,
    this.db,
    this.clock,
    this.hlc,
    this.engine,
    this.repo,
  );

  static Future<CatalogNode> create(
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
    final engine = SyncEngine(
      db: db,
      hlc: hlc,
      registry: registry,
      transport: InMemoryTransport(folder, deviceId),
      deviceId: deviceId,
    );
    final repo = CatalogRepository(
      db: db,
      changeLog: changeLog,
      hlcService: hlc,
      clock: clock,
    );
    return CatalogNode._(deviceId, db, clock, hlc, engine, repo);
  }

  Future<void> close() => db.close();
}

Future<CatalogRepository> singleRepo() async {
  final node = await CatalogNode.create('solo', InMemoryFolder(), 1000);
  return node.repo;
}

void main() {
  group('CatalogRepository', () {
    test('savePart creates a product + variant visible in watch()', () async {
      final repo = await singleRepo();
      await repo.savePart(
        const PartDraft(
          name: 'Brake Pad Set',
          sku: 'BP-100',
          brandName: 'Bosch',
          price: Money(2500),
          cost: Money(1500),
          coreCharge: Money(0),
        ),
      );

      final items = await repo.watch().first;
      expect(items.length, 1);
      expect(items.first.sku, 'BP-100');
      expect(items.first.productName, 'Brake Pad Set');
      expect(items.first.brandName, 'Bosch');
      expect(items.first.price, const Money(2500));
    });

    test('a product can carry several variants, each sellable by SKU', () async {
      final repo = await singleRepo();
      final frontId = await repo.savePart(
        const PartDraft(
          name: 'Brake Pad Set',
          sku: 'BP-F',
          brandName: 'Bosch',
          variantName: 'Front',
          price: Money(2500),
          cost: Money(1500),
          coreCharge: Money(0),
        ),
      );
      final front = (await repo.getPart(frontId))!;
      expect(front.variantName, 'Front');

      // Second variant on the SAME product (own SKU/price, shared name/brand).
      final rearId = await repo.savePart(
        PartDraft(
          productId: front.productId,
          name: front.name,
          brandName: front.brandName,
          variantName: 'Rear',
          sku: 'BP-R',
          price: const Money(2200),
          cost: const Money(1300),
          coreCharge: const Money(0),
        ),
      );
      expect(rearId, isNot(frontId));

      // Both are catalog rows of one product, searchable by either SKU.
      final items = await repo.watch().first;
      expect(items, hasLength(2));
      expect(items.map((i) => i.productId).toSet(), hasLength(1));
      expect(
        (await repo.watch(query: 'BP-R').first).single.variantName,
        'Rear',
      );

      // itemsForProduct lists the siblings (ordered by variant name).
      final siblings = await repo.itemsForProduct(front.productId!);
      expect(siblings.map((v) => v.variantName).toList(), ['Front', 'Rear']);

      // Deleting one variant leaves the other sellable.
      await repo.deletePart(rearId);
      expect(await repo.itemsForProduct(front.productId!), hasLength(1));

      await repo.db.close();
    });

    test('savePart updates an existing part in place', () async {
      final repo = await singleRepo();
      final id = await repo.savePart(
        const PartDraft(
          name: 'Oil Filter',
          sku: 'OF-1',
          price: Money(999),
          cost: Money(500),
          coreCharge: Money(0),
        ),
      );

      final draft = await repo.getPart(id);
      expect(draft, isNotNull);
      await repo.savePart(draft!.copyWith(price: const Money(1299)));

      final items = await repo.watch().first;
      expect(items.length, 1, reason: 'update must not duplicate');
      expect(items.first.price, const Money(1299));
    });

    test('deletePart tombstones the variant (hidden from watch)', () async {
      final repo = await singleRepo();
      final id = await repo.savePart(
        const PartDraft(
          name: 'Spark Plug',
          sku: 'SP-9',
          price: Money(450),
          cost: Money(200),
          coreCharge: Money(0),
        ),
      );

      await repo.deletePart(id);
      expect(await repo.watch().first, isEmpty);
    });

    test('search matches sku and product name', () async {
      final repo = await singleRepo();
      await repo.savePart(
        const PartDraft(
          name: 'Air Filter',
          sku: 'AF-1',
          price: Money(800),
          cost: Money(400),
          coreCharge: Money(0),
        ),
      );
      await repo.savePart(
        const PartDraft(
          name: 'Cabin Filter',
          sku: 'CF-2',
          price: Money(900),
          cost: Money(450),
          coreCharge: Money(0),
        ),
      );

      expect((await repo.watch(query: 'AF-1').first).length, 1);
      expect((await repo.watch(query: 'Filter').first).length, 2);
      expect((await repo.watch(query: 'nothing').first), isEmpty);
    });

    test('brand is find-or-created (no duplicates by name)', () async {
      final repo = await singleRepo();
      await repo.savePart(
        const PartDraft(
          name: 'Part A',
          sku: 'A',
          brandName: 'Denso',
          price: Money(100),
          cost: Money(50),
          coreCharge: Money(0),
        ),
      );
      await repo.savePart(
        const PartDraft(
          name: 'Part B',
          sku: 'B',
          brandName: 'Denso',
          price: Money(200),
          cost: Money(80),
          coreCharge: Money(0),
        ),
      );

      final brands = await (repo.db.select(
        repo.db.brands,
      )..where((b) => b.name.equals('Denso'))).get();
      expect(brands.length, 1);
    });

    test(
      'a part (product + variant + brand) replicates to another device',
      () async {
        final folder = InMemoryFolder();
        final a = await CatalogNode.create('device-a', folder, 1000);
        final b = await CatalogNode.create('device-b', folder, 1000);

        await a.repo.savePart(
          const PartDraft(
            name: 'Timing Belt',
            sku: 'TB-7',
            brandName: 'Gates',
            price: Money(4500),
            cost: Money(2600),
            coreCharge: Money(0),
          ),
        );

        await a.engine.sync();
        await b.engine.sync();

        final onB = await b.repo.watch().first;
        expect(onB.length, 1);
        expect(onB.first.sku, 'TB-7');
        expect(onB.first.productName, 'Timing Belt');
        expect(onB.first.brandName, 'Gates', reason: 'brand replicated too');
        expect(onB.first.price, const Money(4500));

        await a.close();
        await b.close();
      },
    );
  });
}
