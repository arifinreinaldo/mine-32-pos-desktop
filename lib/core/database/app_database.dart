import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'tables/catalog_tables.dart';
import 'tables/settings_tables.dart';
import 'tables/sync_tables.dart';

part 'app_database.g.dart';

/// The single application database. Tables are declared here and split across
/// `tables/` by concern; feature DAOs are layered on top in their data layers.
@DriftDatabase(
  tables: [
    // Infrastructure
    CompanySettings,
    Devices,
    ChangeLog,
    AppliedChanges,
    SyncMeta,
    // Catalog
    Brands,
    Categories,
    Products,
    ProductVariants,
    // Automotive catalog
    Vehicles,
    Fitments,
    CrossReferences,
    Supersessions,
  ],
)
class AppDatabase extends _$AppDatabase {
  /// Pass an executor for tests (e.g. `NativeDatabase.memory()`); omit in the
  /// app to open the on-disk database under the OS app-support directory.
  AppDatabase([QueryExecutor? executor]) : super(executor ?? _openOnDisk());

  @override
  int get schemaVersion => 3;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) async {
      await m.createAll();
    },
    onUpgrade: (m, from, to) async {
      // v1 -> v2: catalog tables.
      if (from < 2) {
        await m.createTable(brands);
        await m.createTable(categories);
        await m.createTable(products);
        await m.createTable(productVariants);
      }
      // v2 -> v3: automotive catalog tables.
      if (from < 3) {
        await m.createTable(vehicles);
        await m.createTable(fitments);
        await m.createTable(crossReferences);
        await m.createTable(supersessions);
      }
    },
    beforeOpen: (details) async {
      await customStatement('PRAGMA foreign_keys = ON');
    },
  );

  static QueryExecutor _openOnDisk() {
    return LazyDatabase(() async {
      final supportDir = await getApplicationSupportDirectory();
      final dbFolder = Directory(p.join(supportDir.path, 'Mine32 POS'));
      if (!dbFolder.existsSync()) {
        dbFolder.createSync(recursive: true);
      }
      final file = File(p.join(dbFolder.path, 'mine32.sqlite'));
      return NativeDatabase.createInBackground(file);
    });
  }
}
