import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mine32_pos/core/database/app_database.dart';
import 'package:mine32_pos/core/sync/change_log_writer.dart';
import 'package:mine32_pos/core/sync/core_sync_entities.dart';
import 'package:mine32_pos/core/sync/hlc_service.dart';
import 'package:mine32_pos/core/sync/sync_engine.dart';
import 'package:mine32_pos/core/sync/sync_entity.dart';
import 'package:mine32_pos/core/sync/transport/in_memory_transport.dart';
import 'package:mine32_pos/core/time/clock.dart';
import 'package:mine32_pos/features/inventory/data/inventory_repository.dart';
import 'package:mine32_pos/features/inventory/data/inventory_sync.dart';
import 'package:mine32_pos/features/inventory/domain/movement_reason.dart';
import 'package:mine32_pos/features/inventory/domain/stock_models.dart';

class InvNode {
  final AppDatabase db;
  final SyncEngine engine;
  final InventoryRepository repo;
  InvNode._(this.db, this.engine, this.repo);

  static Future<InvNode> create(
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
    registerInventorySyncEntities(registry);
    final engine = SyncEngine(
      db: db,
      hlc: hlc,
      registry: registry,
      transport: InMemoryTransport(folder, deviceId),
      deviceId: deviceId,
    );
    final repo = InventoryRepository(
      db: db,
      changeLog: changeLog,
      hlcService: hlc,
      clock: clock,
    );
    return InvNode._(db, engine, repo);
  }

  Future<void> close() => db.close();
}

void main() {
  group('InventoryRepository', () {
    test('on-hand is the sum of movements', () async {
      final n = await InvNode.create('solo', InMemoryFolder(), 1000);
      await n.repo.addMovement(
        variantId: 'V1',
        locationId: 'L1',
        qty: 10,
        reason: MovementReason.purchase,
      );
      await n.repo.addMovement(
        variantId: 'V1',
        locationId: 'L1',
        qty: -3,
        reason: MovementReason.sale,
      );
      expect(await n.repo.onHand('V1', 'L1'), 7);
      await n.close();
    });

    test('adjustTo appends the difference to reach the target', () async {
      final n = await InvNode.create('solo', InMemoryFolder(), 1000);
      await n.repo.addMovement(
        variantId: 'V1',
        locationId: 'L1',
        qty: 5,
        reason: MovementReason.purchase,
      );
      await n.repo.adjustTo(variantId: 'V1', locationId: 'L1', targetQty: 8);
      expect(await n.repo.onHand('V1', 'L1'), 8);
      await n.repo.adjustTo(variantId: 'V1', locationId: 'L1', targetQty: 2);
      expect(await n.repo.onHand('V1', 'L1'), 2);
      await n.close();
    });

    test('ensureDefaultLocation is idempotent', () async {
      final n = await InvNode.create('solo', InMemoryFolder(), 1000);
      final a = await n.repo.ensureDefaultLocation();
      final b = await n.repo.ensureDefaultLocation();
      expect(a, b);
      expect((await n.repo.watchLocations().first).length, 1);
      await n.close();
    });

    test(
      'NO LOST STOCK: concurrent offline movements both count after sync',
      () async {
        final folder = InMemoryFolder();
        final a = await InvNode.create('device-a', folder, 1000);
        final b = await InvNode.create('device-b', folder, 1000);

        // Both devices adjust the same variant/location while "offline".
        await a.repo.addMovement(
          variantId: 'V1',
          locationId: 'L1',
          qty: 5,
          reason: MovementReason.purchase,
        );
        await b.repo.addMovement(
          variantId: 'V1',
          locationId: 'L1',
          qty: 3,
          reason: MovementReason.purchase,
        );

        // Exchange bundles both ways.
        await a.engine.sync();
        await b.engine.sync();
        await a.engine.sync();

        expect(await a.repo.onHand('V1', 'L1'), 8, reason: 'A sees both');
        expect(await b.repo.onHand('V1', 'L1'), 8, reason: 'B sees both');

        await a.close();
        await b.close();
      },
    );

    test('locations replicate as master data', () async {
      final folder = InMemoryFolder();
      final a = await InvNode.create('device-a', folder, 1000);
      final b = await InvNode.create('device-b', folder, 1000);

      await a.repo.upsertLocation(
        const LocationDraft(name: 'Warehouse 1', type: 'warehouse'),
      );
      await a.engine.sync();
      await b.engine.sync();

      final onB = await b.repo.watchLocations().first;
      expect(onB.map((l) => l.name), contains('Warehouse 1'));

      await a.close();
      await b.close();
    });
  });
}
