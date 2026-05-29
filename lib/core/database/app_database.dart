import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'tables/settings_tables.dart';
import 'tables/sync_tables.dart';

part 'app_database.g.dart';

/// The single application database. Tables are declared here and split across
/// `tables/` by concern; feature DAOs are layered on top in their data layers.
@DriftDatabase(
  tables: [CompanySettings, Devices, ChangeLog, AppliedChanges, SyncMeta],
)
class AppDatabase extends _$AppDatabase {
  /// Pass an executor for tests (e.g. `NativeDatabase.memory()`); omit in the
  /// app to open the on-disk database under the OS app-support directory.
  AppDatabase([QueryExecutor? executor]) : super(executor ?? _openOnDisk());

  @override
  int get schemaVersion => 1;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) async {
      await m.createAll();
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
