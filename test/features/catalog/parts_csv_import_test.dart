import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mine32_pos/core/database/app_database.dart';
import 'package:mine32_pos/core/sync/change_log_writer.dart';
import 'package:mine32_pos/core/sync/hlc_service.dart';
import 'package:mine32_pos/core/time/clock.dart';
import 'package:mine32_pos/features/catalog/data/catalog_repository.dart';
import 'package:mine32_pos/features/catalog/data/parts_csv_import.dart';

Future<CatalogRepository> _repo(AppDatabase db) async {
  final clock = MutableClock(1000);
  final hlc = HlcService(db, clock, 'dev');
  await hlc.load();
  return CatalogRepository(
    db: db,
    changeLog: ChangeLogWriter(db, 'dev'),
    hlcService: hlc,
    clock: clock,
  );
}

void main() {
  test('imports new parts with values at the given scale', () async {
    final db = AppDatabase(NativeDatabase.memory());
    final catalog = await _repo(db);
    final importer = PartsCsvImporter(catalog: catalog, scale: 2);
    const csv =
        'name,sku,brand,price,cost,barcode,active\n'
        'Brake Pad,BP-1,Bosch,25.00,15.00,8990001,true\n'
        'Oil Filter,OF-2,Denso,4.50,2.50,,false\n';

    final r = await importer.import(csv);
    expect(r.created, 2);
    expect(r.updated, 0);
    expect(r.hasErrors, isFalse);

    final items = await catalog.watch().first;
    final bp = items.firstWhere((i) => i.sku == 'BP-1');
    expect(bp.price.minorUnits, 2500);
    expect(bp.cost.minorUnits, 1500);
    expect(bp.brandName, 'Bosch');
    expect(bp.barcode, '8990001');
    final of = items.firstWhere((i) => i.sku == 'OF-2');
    expect(of.isActive, isFalse);

    await db.close();
  });

  test('re-importing the same SKU updates instead of duplicating', () async {
    final db = AppDatabase(NativeDatabase.memory());
    final catalog = await _repo(db);
    final importer = PartsCsvImporter(catalog: catalog, scale: 2);
    await importer.import('name,sku,price\nBrake Pad,BP-1,25.00\n');
    final r = await importer.import(
      'name,sku,price\nBrake Pad XL,BP-1,30.00\n',
    );

    expect(r.created, 0);
    expect(r.updated, 1);
    final items = await catalog.watch().first;
    expect(items.where((i) => i.sku == 'BP-1'), hasLength(1));
    expect(items.single.price.minorUnits, 3000);
    expect(items.single.productName, 'Brake Pad XL');

    await db.close();
  });

  test(
    'header aliases map make->brand and part number->sku (IDR scale)',
    () async {
      final db = AppDatabase(NativeDatabase.memory());
      final catalog = await _repo(db);
      final importer = PartsCsvImporter(catalog: catalog, scale: 0);
      final r = await importer.import(
        'product name,part number,make,sell price\nAir Filter,AF-9,Mann,80000\n',
      );

      expect(r.created, 1);
      final item = (await catalog.watch().first).single;
      expect(item.sku, 'AF-9');
      expect(item.brandName, 'Mann');
      expect(item.price.minorUnits, 80000); // scale 0 → no implicit ×100

      await db.close();
    },
  );

  test(
    'missing required column returns an error and imports nothing',
    () async {
      final db = AppDatabase(NativeDatabase.memory());
      final catalog = await _repo(db);
      final r = await PartsCsvImporter(
        catalog: catalog,
        scale: 2,
      ).import('foo,bar\n1,2\n');

      expect(r.total, 0);
      expect(r.hasErrors, isTrue);

      await db.close();
    },
  );

  test('invalid money and missing name are reported per line', () async {
    final db = AppDatabase(NativeDatabase.memory());
    final catalog = await _repo(db);
    final importer = PartsCsvImporter(catalog: catalog, scale: 2);
    const csv =
        'name,sku,price\n'
        'Good,G-1,10.00\n'
        'Bad price,B-1,abc\n'
        ',NO-NAME,5.00\n';

    final r = await importer.import(csv);
    expect(r.created, 1);
    expect(r.skipped, 2);
    expect(r.errors, hasLength(2));
    expect((await catalog.watch().first).single.sku, 'G-1');

    await db.close();
  });

  test('template round-trips through the importer', () async {
    final db = AppDatabase(NativeDatabase.memory());
    final catalog = await _repo(db);
    final r = await PartsCsvImporter(
      catalog: catalog,
      scale: 0,
    ).import(PartsCsvImporter.template());

    expect(r.created, 2);
    expect(r.hasErrors, isFalse);

    await db.close();
  });
}
