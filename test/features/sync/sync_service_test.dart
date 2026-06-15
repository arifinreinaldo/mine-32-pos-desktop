import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mine32_pos/core/database/app_database.dart';
import 'package:mine32_pos/core/di/app_services.dart';
import 'package:mine32_pos/core/money/money.dart';
import 'package:mine32_pos/core/time/clock.dart';
import 'package:mine32_pos/core/sync/sync_engine.dart';
import 'package:mine32_pos/features/catalog/data/catalog_repository.dart';
import 'package:mine32_pos/features/catalog/domain/part_draft.dart';
import 'package:mine32_pos/features/sync/data/sync_service.dart';

Future<(AppServices, SyncService)> _node(String deviceId, int t) async {
  final services = await AppServices.initialize(
    database: AppDatabase(NativeDatabase.memory()),
    clock: MutableClock(t),
  );
  return (services, SyncService(services));
}

CatalogRepository _catalog(AppServices s) => CatalogRepository(
  db: s.db,
  changeLog: s.changeLog,
  hlcService: s.hlc,
  clock: s.clock,
);

void main() {
  test(
    'SyncService replicates through a real shared folder (no server)',
    () async {
      final dir = await Directory.systemTemp.createTemp('mine32-sync-test');
      addTearDown(() => dir.delete(recursive: true));

      final (servicesA, syncA) = await _node('device-a', 1000);
      final (servicesB, syncB) = await _node('device-b', 1000);
      await syncA.setFolderPath(dir.path);
      await syncB.setFolderPath(dir.path);

      await _catalog(servicesA).savePart(
        const PartDraft(
          name: 'Clutch Kit',
          sku: 'CK-1',
          brandName: 'Exedy',
          price: Money(50000),
          cost: Money(30000),
          coreCharge: Money(0),
        ),
      );

      expect(await syncA.pendingCount(), greaterThan(0));
      final exportResult = await syncA.syncNow();
      expect(exportResult.exported, greaterThan(0));
      expect(await syncA.pendingCount(), 0, reason: 'outbox flushed');

      // A bundle file now exists in the shared folder.
      final files = dir
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.json'))
          .toList();
      expect(files, isNotEmpty);

      // B imports it.
      final importResult = await syncB.syncNow();
      expect(importResult.imported, greaterThan(0));

      final onB = await _catalog(servicesB).watch(query: 'CK-1').first;
      expect(onB.length, 1);
      expect(onB.first.brandName, 'Exedy');

      // The pass was recorded in the local history (newest first).
      final histA = await syncA.recentRuns();
      expect(histA, isNotEmpty);
      expect(histA.first.exported, exportResult.exported);

      await servicesA.dispose();
      await servicesB.dispose();
    },
  );

  test('recordRun keeps a newest-first history, capped at 20', () async {
    final (services, sync) = await _node('solo', 1000);
    addTearDown(services.dispose);

    expect(await sync.recentRuns(), isEmpty);

    for (var i = 1; i <= 25; i++) {
      await sync.recordRun(
        SyncResult(exported: i, imported: 0),
        at: DateTime.fromMillisecondsSinceEpoch(i * 1000),
      );
    }

    final runs = await sync.recentRuns();
    expect(runs, hasLength(20)); // capped
    expect(runs.first.exported, 25); // newest first
    expect(runs.last.exported, 6); // oldest kept (25 - 20 + 1)
  });
}
