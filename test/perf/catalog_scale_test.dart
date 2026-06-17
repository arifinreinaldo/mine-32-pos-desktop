import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mine32_pos/core/database/app_database.dart';
import 'package:mine32_pos/core/sync/change_log_writer.dart';
import 'package:mine32_pos/core/sync/hlc_service.dart';
import 'package:mine32_pos/core/time/clock.dart';
import 'package:mine32_pos/features/catalog/data/catalog_repository.dart';

/// Scale check for the catalog: bulk-insert a large catalog (bypassing the
/// change-log for speed) and confirm search stays correct and quick. Guards
/// against an accidental O(n²) / missing-index regression in catalog search.
void main() {
  test('catalog search is correct and quick at 20k variants', () async {
    const n = 20000;
    final db = AppDatabase(NativeDatabase.memory());
    final clock = MutableClock(1000);
    final hlc = HlcService(db, clock, 'dev');
    await hlc.load();
    final catalog = CatalogRepository(
      db: db,
      changeLog: ChangeLogWriter(db, 'dev'),
      hlcService: hlc,
      clock: clock,
    );

    // Bulk insert N products + their default variants in one batch.
    final products = <Product>[];
    final variants = <ProductVariant>[];
    for (var i = 0; i < n; i++) {
      final id = 'p$i';
      products.add(
        Product(
          id: id,
          createdAt: 0,
          updatedAt: 0,
          updatedHlc: '0',
          name: 'Spark Plug $i',
          unit: 'each',
          isActive: true,
          skuRoot: 'SP-$i',
        ),
      );
      variants.add(
        ProductVariant(
          id: 'v$i',
          createdAt: 0,
          updatedAt: 0,
          updatedHlc: '0',
          productId: id,
          sku: 'SP-$i',
          name: 'Default',
          priceMinor: 1000 + i,
          wholesalePriceMinor: 0,
          costMinor: 500,
          coreChargeMinor: 0,
          reorderPoint: 0,
          isActive: true,
        ),
      );
    }
    await db.batch((b) {
      b.insertAll(db.products, products);
      b.insertAll(db.productVariants, variants);
    });

    // A specific-SKU search returns exactly the one matching variant…
    final sw = Stopwatch()..start();
    final hit = await catalog.watch(query: 'SP-19999').first;
    sw.stop();
    expect(hit, hasLength(1));
    expect(hit.single.sku, 'SP-19999');
    // …well under a generous bound (a full LIKE scan of 20k is still fast).
    expect(
      sw.elapsedMilliseconds,
      lessThan(2000),
      reason: 'search took ${sw.elapsedMilliseconds}ms',
    );

    // An empty query lists everything; a prefix narrows correctly.
    expect(await catalog.list(), hasLength(n));
    expect(
      await catalog.list(query: 'SP-1999'),
      hasLength(11),
    ); // 1999, 19990-9

    await db.close();
  });
}
