import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mine32_pos/core/database/app_database.dart';
import 'package:mine32_pos/core/database/sync_repository.dart';
import 'package:mine32_pos/core/sync/change_log_writer.dart';
import 'package:mine32_pos/core/sync/change_record.dart';
import 'package:mine32_pos/core/sync/core_sync_entities.dart';
import 'package:mine32_pos/core/sync/hlc_service.dart';
import 'package:mine32_pos/core/sync/sync_engine.dart';
import 'package:mine32_pos/core/sync/sync_entity.dart';
import 'package:mine32_pos/core/sync/transport/in_memory_transport.dart';
import 'package:mine32_pos/core/time/clock.dart';
import 'package:mine32_pos/core/time/hlc.dart';

/// A simulated device/installation with its own DB + clock, sharing a folder.
class Node {
  final String deviceId;
  final AppDatabase db;
  final MutableClock clock;
  final HlcService hlc;
  final ChangeLogWriter changeLog;
  final SyncRegistry registry;
  final SyncEngine engine;
  late final CompanyRepo company;

  Node._(
    this.deviceId,
    this.db,
    this.clock,
    this.hlc,
    this.changeLog,
    this.registry,
    this.engine,
  ) {
    company = CompanyRepo(this);
  }

  factory Node(String deviceId, InMemoryFolder folder, int startMillis) {
    final db = AppDatabase(NativeDatabase.memory());
    final clock = MutableClock(startMillis);
    final hlc = HlcService(db, clock, deviceId);
    final changeLog = ChangeLogWriter(db, deviceId);
    final registry = SyncRegistry();
    registerCoreSyncEntities(registry);
    final engine = SyncEngine(
      db: db,
      hlc: hlc,
      registry: registry,
      transport: InMemoryTransport(folder, deviceId),
      deviceId: deviceId,
    );
    return Node._(deviceId, db, clock, hlc, changeLog, registry, engine);
  }

  Future<void> init() => hlc.load();

  Future<CompanySetting?> readCompany(String id) => (db.select(
    db.companySettings,
  )..where((t) => t.id.equals(id))).getSingleOrNull();

  Future<int> companyCount() async =>
      (await db.select(db.companySettings).get()).length;

  Future<void> close() => db.close();
}

class CompanyRepo extends SyncRepository {
  CompanyRepo(Node n)
    : super(
        db: n.db,
        changeLog: n.changeLog,
        hlcService: n.hlc,
        clock: n.clock,
      );

  Future<void> upsert({
    required String id,
    required String name,
    int? deletedAt,
  }) async {
    await writeSyncable<CompanySetting>(
      entityTable: 'company_settings',
      table: db.companySettings,
      rowId: id,
      op: deletedAt == null ? ChangeOp.upsert : ChangeOp.delete,
      build: (hlc, now) => CompanySetting(
        id: id,
        createdAt: now,
        updatedAt: now,
        deletedAt: deletedAt,
        updatedHlc: hlc.pack(),
        name: name,
        currency: 'USD',
        currencyScale: 2,
        isPkp: false,
        taxInclusive: true,
      ),
    );
  }
}

/// Exchange bundles both ways until quiescent (no node has anything to push).
Future<void> fullSync(List<Node> nodes) async {
  for (var round = 0; round < 3; round++) {
    var changed = false;
    for (final n in nodes) {
      final r = await n.engine.sync();
      if (r.changed) changed = true;
    }
    if (!changed) break;
  }
}

void main() {
  group('SyncEngine (serverless, offline-first)', () {
    test('a change on one device propagates to another', () async {
      final folder = InMemoryFolder();
      final a = Node('device-a', folder, 1000);
      final b = Node('device-b', folder, 1000);
      await a.init();
      await b.init();

      await a.company.upsert(id: 'default', name: 'Acme Parts');
      await fullSync([a, b]);

      final onB = await b.readCompany('default');
      expect(onB, isNotNull);
      expect(onB!.name, 'Acme Parts');

      await a.close();
      await b.close();
    });

    test('re-importing is idempotent (no duplicates, no errors)', () async {
      final folder = InMemoryFolder();
      final a = Node('device-a', folder, 1000);
      final b = Node('device-b', folder, 1000);
      await a.init();
      await b.init();

      await a.company.upsert(id: 'default', name: 'Acme Parts');
      await a.engine.export();
      // Import several times.
      await b.engine.import();
      await b.engine.import();
      await b.engine.import();

      expect(await b.companyCount(), 1);
      expect((await b.readCompany('default'))!.name, 'Acme Parts');

      await a.close();
      await b.close();
    });

    test(
      'concurrent edits converge via HLC last-write-wins, any order',
      () async {
        // A edits later (higher wall clock) than B -> A must win on both nodes.
        final folder = InMemoryFolder();
        final a = Node('device-a', folder, 5000); // later
        final b = Node('device-b', folder, 1000); // earlier
        await a.init();
        await b.init();

        await a.company.upsert(id: 'default', name: 'From A (newer)');
        await b.company.upsert(id: 'default', name: 'From B (older)');

        await fullSync([a, b]);

        expect((await a.readCompany('default'))!.name, 'From A (newer)');
        expect((await b.readCompany('default'))!.name, 'From A (newer)');

        await a.close();
        await b.close();
      },
    );

    test('order of bundle application does not affect the result', () async {
      // Apply B-then-A on one receiver and A-then-B on another; both converge.
      final folderForX = InMemoryFolder();
      final folderForY = InMemoryFolder();

      final a1 = Node('device-a', folderForX, 5000);
      final b1 = Node('device-b', folderForX, 1000);
      final a2 = Node('device-a', folderForY, 5000);
      final b2 = Node('device-b', folderForY, 1000);
      for (final n in [a1, b1, a2, b2]) {
        await n.init();
      }

      await a1.company.upsert(id: 'default', name: 'A-newer');
      await b1.company.upsert(id: 'default', name: 'B-older');
      await a2.company.upsert(id: 'default', name: 'A-newer');
      await b2.company.upsert(id: 'default', name: 'B-older');

      // Export everyone so both bundles exist in each folder.
      await a1.engine.export();
      await b1.engine.export();
      await a2.engine.export();
      await b2.engine.export();

      // Receiver X imports (sorted order is deterministic); receiver Y too.
      final receiverX = Node('device-x', folderForX, 9000);
      final receiverY = Node('device-y', folderForY, 9000);
      await receiverX.init();
      await receiverY.init();

      await receiverX.engine.import();
      await receiverY.engine.import();

      expect(
        (await receiverX.readCompany('default'))!.name,
        (await receiverY.readCompany('default'))!.name,
      );
      expect((await receiverX.readCompany('default'))!.name, 'A-newer');

      for (final n in [a1, b1, a2, b2, receiverX, receiverY]) {
        await n.close();
      }
    });

    test(
      'tombstone wins over a concurrent older update (no resurrection)',
      () async {
        final folder = InMemoryFolder();
        final a = Node('device-a', folder, 1000);
        final b = Node('device-b', folder, 1000);
        await a.init();
        await b.init();

        // Create on A and replicate to B.
        a.clock.millis = 1000;
        await a.company.upsert(id: 'default', name: 'Initial');
        await fullSync([a, b]);
        expect(await b.readCompany('default'), isNotNull);

        // B updates (older), A deletes (newer).
        b.clock.millis = 2000;
        await b.company.upsert(id: 'default', name: 'B late edit');
        a.clock.millis = 3000;
        await a.company.upsert(id: 'default', name: 'Initial', deletedAt: 3000);

        await fullSync([a, b]);

        final onA = await a.readCompany('default');
        final onB = await b.readCompany('default');
        expect(onA!.deletedAt, isNotNull, reason: 'A stays deleted');
        expect(
          onB!.deletedAt,
          isNotNull,
          reason: 'B must not resurrect the row',
        );

        await a.close();
        await b.close();
      },
    );

    test('import does not skip an un-applied (unknown-entity) bundle', () async {
      // Two bundles from peer 'a': an earlier one with an UNKNOWN entity, and a
      // later one with a known entity. The cursor must NOT advance past the
      // unknown bundle (so it is retried once this device learns the entity).
      final folder = InMemoryFolder();
      final h1 = const Hlc(millis: 1000, counter: 0, nodeId: 'a');
      final h2 = const Hlc(millis: 2000, counter: 0, nodeId: 'a');

      final unknownBundle = SyncBundle(
        schemaVersion: 1,
        deviceId: 'a',
        fromHlc: h1.pack(),
        toHlc: h1.pack(),
        changes: [
          ChangeRecord(
            id: 'c1',
            entityTable: 'mystery', // not in the registry
            rowId: 'm1',
            op: ChangeOp.upsert,
            payload: const {'id': 'm1'},
            hlc: h1,
            deviceId: 'a',
            createdAt: 1000,
          ),
        ],
      );
      final company = CompanySetting(
        id: 'default',
        createdAt: 2000,
        updatedAt: 2000,
        updatedHlc: h2.pack(),
        name: 'From A',
        currency: 'USD',
        currencyScale: 2,
        isPkp: false,
        taxInclusive: true,
      );
      final knownBundle = SyncBundle(
        schemaVersion: 1,
        deviceId: 'a',
        fromHlc: h2.pack(),
        toHlc: h2.pack(),
        changes: [
          ChangeRecord(
            id: 'c2',
            entityTable: 'company_settings',
            rowId: 'default',
            op: ChangeOp.upsert,
            payload: company.toJson(),
            hlc: h2,
            deviceId: 'a',
            createdAt: 2000,
          ),
        ],
      );
      folder.data['a'] = {
        SyncEngine.bundleName(h1.pack()): utf8.encode(
          jsonEncode(unknownBundle.toJson()),
        ),
        SyncEngine.bundleName(h2.pack()): utf8.encode(
          jsonEncode(knownBundle.toJson()),
        ),
      };

      final db = AppDatabase(NativeDatabase.memory());
      final hlc = HlcService(db, MutableClock(5000), 'b');
      await hlc.load();
      final registry = SyncRegistry();
      registerCoreSyncEntities(
        registry,
      ); // knows company_settings, not 'mystery'
      final engine = SyncEngine(
        db: db,
        hlc: hlc,
        registry: registry,
        transport: InMemoryTransport(folder, 'b'),
        deviceId: 'b',
      );

      final applied = await engine.import();
      expect(applied, 1, reason: 'only the known company change applies');

      final onB = await (db.select(
        db.companySettings,
      )..where((t) => t.id.equals('default'))).getSingleOrNull();
      expect(onB?.name, 'From A');

      final cursorRow = await (db.select(
        db.syncMeta,
      )..where((t) => t.key.equals('sync.cursor.a'))).getSingleOrNull();
      expect(
        cursorRow?.value ?? '',
        '',
        reason: 'cursor must not advance past the un-applied mystery bundle',
      );

      await db.close();
    });
  });
}
