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
import 'package:mine32_pos/features/catalog/data/auto_parts_repository.dart';
import 'package:mine32_pos/features/catalog/data/catalog_repository.dart';
import 'package:mine32_pos/features/catalog/data/catalog_sync.dart';
import 'package:mine32_pos/features/catalog/domain/auto_parts_models.dart';
import 'package:mine32_pos/features/catalog/domain/part_draft.dart';

class Node {
  final AppDatabase db;
  final SyncEngine engine;
  final CatalogRepository catalog;
  final AutoPartsRepository auto;
  Node._(this.db, this.engine, this.catalog, this.auto);

  static Future<Node> create(
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
    final catalog = CatalogRepository(
      db: db,
      changeLog: changeLog,
      hlcService: hlc,
      clock: clock,
    );
    final auto = AutoPartsRepository(
      db: db,
      changeLog: changeLog,
      hlcService: hlc,
      clock: clock,
    );
    return Node._(db, engine, catalog, auto);
  }

  Future<void> close() => db.close();
}

Future<Node> solo() => Node.create('solo', InMemoryFolder(), 1000);

void main() {
  group('AutoPartsRepository', () {
    test(
      'fitment links a variant to a vehicle and reads back with a label',
      () async {
        final n = await solo();
        final variantId = await n.catalog.savePart(
          const PartDraft(
            name: 'Brake Pad',
            sku: 'BP-1',
            price: Money(2500),
            cost: Money(1500),
            coreCharge: Money(0),
          ),
        );
        final vehicleId = await n.auto.upsertVehicle(
          const VehicleDraft(
            make: 'Toyota',
            model: 'Corolla',
            yearFrom: 2015,
            yearTo: 2018,
            engine: '1.8L',
          ),
        );
        await n.auto.addFitment(variantId: variantId, vehicleId: vehicleId);

        final fitments = await n.auto.watchFitments(variantId).first;
        expect(fitments.length, 1);
        expect(fitments.first.vehicleLabel, 'Toyota Corolla 2015-2018 1.8L');

        await n.close();
      },
    );

    test(
      'cross-reference lookup finds a variant by interchange number',
      () async {
        final n = await solo();
        final variantId = await n.catalog.savePart(
          const PartDraft(
            name: 'Oil Filter',
            sku: 'OF-1',
            price: Money(999),
            cost: Money(500),
            coreCharge: Money(0),
          ),
        );
        await n.auto.addCrossReference(
          variantId: variantId,
          otherNumber: 'OEM-90915',
          otherBrand: 'Toyota',
          refType: 'oem',
        );

        expect(
          await n.auto.watchCrossReferences(variantId).first,
          hasLength(1),
        );
        expect(
          await n.auto.lookupVariantIdsByNumber('OEM-90915'),
          contains(variantId),
        );
        // Also findable by its own SKU.
        expect(
          await n.auto.lookupVariantIdsByNumber('OF-1'),
          contains(variantId),
        );

        await n.close();
      },
    );

    test(
      'findOrCreateVehicle dedupes by attributes, listVehicles sorts',
      () async {
        final n = await solo();
        final id1 = await n.auto.findOrCreateVehicle(
          const VehicleDraft(
            make: 'Toyota',
            model: 'Corolla',
            yearFrom: 2015,
            yearTo: 2018,
            engine: '1.8L',
          ),
        );
        // Same attributes (different case/whitespace) reuse the same vehicle.
        final id2 = await n.auto.findOrCreateVehicle(
          const VehicleDraft(
            make: 'toyota',
            model: '  Corolla ',
            yearFrom: 2015,
            yearTo: 2018,
            engine: '1.8l',
          ),
        );
        expect(id2, id1);
        // Different attributes create a new vehicle.
        final id3 = await n.auto.findOrCreateVehicle(
          const VehicleDraft(make: 'Honda', model: 'Civic', engine: '2.0L'),
        );
        expect(id3, isNot(id1));

        final all = await n.auto.listVehicles();
        expect(all.map((v) => v.make).toList(), ['Honda', 'Toyota']);

        await n.close();
      },
    );

    test('removeCrossReference tombstones the reference', () async {
      final n = await solo();
      final variantId = await n.catalog.savePart(
        const PartDraft(
          name: 'Air Filter',
          sku: 'AF-1',
          price: Money(800),
          cost: Money(400),
          coreCharge: Money(0),
        ),
      );
      await n.auto.addCrossReference(variantId: variantId, otherNumber: 'X-1');
      final before = await n.auto.watchCrossReferences(variantId).first;
      expect(before, hasLength(1));
      await n.auto.removeCrossReference(before.first.id);
      expect(await n.auto.watchCrossReferences(variantId).first, isEmpty);

      await n.close();
    });

    test('vehicle + fitment replicate to another device', () async {
      final folder = InMemoryFolder();
      final a = await Node.create('device-a', folder, 1000);
      final b = await Node.create('device-b', folder, 1000);

      final variantId = await a.catalog.savePart(
        const PartDraft(
          name: 'Wiper Blade',
          sku: 'WB-22',
          price: Money(1200),
          cost: Money(600),
          coreCharge: Money(0),
        ),
      );
      final vehicleId = await a.auto.upsertVehicle(
        const VehicleDraft(make: 'Honda', model: 'Civic', engine: '2.0L'),
      );
      await a.auto.addFitment(variantId: variantId, vehicleId: vehicleId);

      await a.engine.sync();
      await b.engine.sync();

      final onB = await b.auto.watchFitments(variantId).first;
      expect(onB.length, 1);
      expect(onB.first.vehicleLabel, 'Honda Civic 2.0L');

      await a.close();
      await b.close();
    });
  });
}
