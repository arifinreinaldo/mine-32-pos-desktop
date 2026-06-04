import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mine32_pos/core/database/app_database.dart';
import 'package:mine32_pos/core/di/app_services.dart';
import 'package:mine32_pos/core/money/money.dart';
import 'package:mine32_pos/core/time/clock.dart';
import 'package:mine32_pos/features/catalog/data/catalog_repository.dart';
import 'package:mine32_pos/features/catalog/domain/part_draft.dart';

/// Mirrors the query behind `pendingChangesProvider` (un-exported change_log
/// rows), which drives the sync status badge in the shell.
Future<int> _pending(AppDatabase db) async {
  final countExpr = db.changeLog.id.count();
  final query = db.selectOnly(db.changeLog)
    ..addColumns([countExpr])
    ..where(db.changeLog.exported.equals(false));
  final row = await query.getSingle();
  return row.read(countExpr) ?? 0;
}

void main() {
  test(
    'pending count: seeded > 0, drops to 0 on export, rises on a change',
    () async {
      final services = await AppServices.initialize(
        database: AppDatabase(NativeDatabase.memory()),
        clock: MutableClock(1000),
      );
      addTearDown(services.dispose);
      final db = services.db;

      // Seeding (accounts, tax rate, settings) produced local changes to sync.
      expect(await _pending(db), greaterThan(0));

      // A completed export marks everything exported → nothing pending.
      await db
          .update(db.changeLog)
          .write(const ChangeLogCompanion(exported: Value(true)));
      expect(await _pending(db), 0);

      // A new local change becomes pending again.
      await CatalogRepository(
        db: db,
        changeLog: services.changeLog,
        hlcService: services.hlc,
        clock: services.clock,
      ).savePart(
        const PartDraft(
          name: 'Brake Pad',
          sku: 'BP-1',
          price: Money(2500),
          cost: Money(1500),
          coreCharge: Money(0),
        ),
      );
      expect(await _pending(db), greaterThan(0));
    },
  );
}
