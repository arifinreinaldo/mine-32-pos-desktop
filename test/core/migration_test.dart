import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mine32_pos/core/database/app_database.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';

/// The original v1 schema (infrastructure tables only), created by hand so we
/// can exercise the real onUpgrade(1 -> current) chain end to end.
const _v1Ddl = <String>[
  '''
  CREATE TABLE company_settings (
    id TEXT NOT NULL PRIMARY KEY,
    created_at INTEGER NOT NULL,
    updated_at INTEGER NOT NULL,
    deleted_at INTEGER,
    updated_hlc TEXT NOT NULL,
    name TEXT NOT NULL DEFAULT 'My Auto Parts',
    legal_name TEXT,
    address TEXT,
    phone TEXT,
    email TEXT,
    tax_number TEXT,
    currency TEXT NOT NULL DEFAULT 'USD',
    currency_scale INTEGER NOT NULL DEFAULT 2,
    receipt_header TEXT,
    receipt_footer TEXT,
    logo_path TEXT
  )''',
  '''
  CREATE TABLE devices (
    id TEXT NOT NULL PRIMARY KEY,
    created_at INTEGER NOT NULL,
    updated_at INTEGER NOT NULL,
    deleted_at INTEGER,
    updated_hlc TEXT NOT NULL,
    name TEXT NOT NULL,
    platform TEXT,
    last_seen_hlc TEXT
  )''',
  '''
  CREATE TABLE change_log (
    id TEXT NOT NULL PRIMARY KEY,
    entity_table TEXT NOT NULL,
    row_id TEXT NOT NULL,
    operation TEXT NOT NULL,
    payload TEXT NOT NULL,
    hlc TEXT NOT NULL,
    device_id TEXT NOT NULL,
    exported INTEGER NOT NULL DEFAULT 0,
    created_at INTEGER NOT NULL
  )''',
  '''
  CREATE TABLE applied_changes (
    change_id TEXT NOT NULL PRIMARY KEY,
    source_device_id TEXT NOT NULL,
    applied_at INTEGER NOT NULL
  )''',
  '''
  CREATE TABLE sync_meta (
    key TEXT NOT NULL PRIMARY KEY,
    value TEXT NOT NULL
  )''',
];

void main() {
  test(
    'upgrades a v1 database to the current schema, preserving data',
    () async {
      final dir = await Directory.systemTemp.createTemp('mine32-migration');
      addTearDown(() => dir.delete(recursive: true));
      final path = p.join(dir.path, 'old.sqlite');

      // Build a v1 database by hand and put some data in it.
      final raw = sqlite3.open(path);
      for (final ddl in _v1Ddl) {
        raw.execute(ddl);
      }
      raw.execute(
        "INSERT INTO sync_meta (key, value) VALUES ('device.id', 'dev-1')",
      );
      raw.execute('PRAGMA user_version = 1');
      raw.close();

      // Opening as the current AppDatabase runs onUpgrade(1 -> schemaVersion).
      final db = AppDatabase(NativeDatabase(File(path)));

      // New tables from later versions now exist and are queryable.
      expect(await db.select(db.customerReceipts).get(), isEmpty);
      expect(await db.select(db.supplierPayments).get(), isEmpty);
      expect(await db.select(db.purchaseOrders).get(), isEmpty);
      expect(await db.select(db.accounts).get(), isEmpty);
      expect(await db.select(db.stockMovements).get(), isEmpty);
      expect(await db.select(db.salesReturns).get(), isEmpty);
      expect(await db.select(db.salesReturnLines).get(), isEmpty);

      // Columns added by later migrations exist (querying company_settings would
      // fail if isPkp/taxInclusive/defaultTaxRateId were missing).
      expect(await db.select(db.companySettings).get(), isEmpty);

      // Original data survived the upgrade.
      final meta = await (db.select(
        db.syncMeta,
      )..where((t) => t.key.equals('device.id'))).getSingleOrNull();
      expect(meta?.value, 'dev-1');

      await db.close();
    },
  );
}
