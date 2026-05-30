import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../../../core/database/app_database.dart';
import '../../../core/database/sync_repository.dart';
import '../../../core/money/money.dart';
import '../../../core/sync/change_record.dart';
import '../domain/catalog_item.dart';
import '../domain/part_draft.dart';

/// Reads and writes the catalog (products, variants, brands). All mutations go
/// through [SyncRepository.writeSyncable] so they replicate. Reads are reactive
/// (Drift streams) and update automatically when sync merges remote changes.
class CatalogRepository extends SyncRepository {
  final Uuid _uuid;

  CatalogRepository({
    required super.db,
    required super.changeLog,
    required super.hlcService,
    required super.clock,
    Uuid? uuid,
  }) : _uuid = uuid ?? const Uuid();

  /// Reactive list of catalog items, optionally filtered by [query]
  /// (matches SKU, barcode or product name). Excludes tombstoned rows.
  Stream<List<CatalogItem>> watch({String query = ''}) {
    final v = db.productVariants;
    final p = db.products;
    final b = db.brands;

    final statement = db.select(v).join([
      innerJoin(p, p.id.equalsExp(v.productId)),
      leftOuterJoin(b, b.id.equalsExp(p.brandId)),
    ]);

    var predicate = v.deletedAt.isNull() & p.deletedAt.isNull();
    final trimmed = query.trim();
    if (trimmed.isNotEmpty) {
      final like = '%$trimmed%';
      predicate =
          predicate &
          (v.sku.like(like) | p.name.like(like) | v.barcode.like(like));
    }
    statement
      ..where(predicate)
      ..orderBy([OrderingTerm.asc(p.name)]);

    return statement.watch().map(
      (rows) => rows.map((row) {
        final variant = row.readTable(v);
        final product = row.readTable(p);
        final brand = row.readTableOrNull(b);
        return _toItem(variant, product, brand);
      }).toList(),
    );
  }

  /// Load a single part for editing.
  Future<PartDraft?> getPart(String variantId) async {
    final variant =
        await (db.select(db.productVariants)
              ..where((t) => t.id.equals(variantId))
              ..limit(1))
            .getSingleOrNull();
    if (variant == null) return null;

    final product =
        await (db.select(db.products)
              ..where((t) => t.id.equals(variant.productId))
              ..limit(1))
            .getSingleOrNull();

    String? brandName;
    final brandId = product?.brandId;
    if (brandId != null) {
      final brand =
          await (db.select(db.brands)
                ..where((t) => t.id.equals(brandId))
                ..limit(1))
              .getSingleOrNull();
      brandName = brand?.name;
    }

    return PartDraft(
      variantId: variant.id,
      productId: variant.productId,
      name: product?.name ?? '',
      sku: variant.sku,
      barcode: variant.barcode,
      brandName: brandName,
      description: product?.description,
      price: Money(variant.priceMinor),
      cost: Money(variant.costMinor),
      coreCharge: Money(variant.coreChargeMinor),
      unit: product?.unit ?? 'each',
      isActive: variant.isActive,
    );
  }

  /// Load a part by its SKU (the first non-deleted match), or null. Used by
  /// CSV import to update an existing part rather than create a duplicate.
  Future<PartDraft?> getPartBySku(String sku) async {
    final variant =
        await (db.select(db.productVariants)
              ..where((t) => t.sku.equals(sku) & t.deletedAt.isNull())
              ..limit(1))
            .getSingleOrNull();
    if (variant == null) return null;
    return getPart(variant.id);
  }

  /// Create or update a simple part (product + default variant, optional brand)
  /// atomically. Returns the variant id.
  Future<String> savePart(PartDraft draft) async {
    return db.transaction(() async {
      String? brandId;
      final brandName = draft.brandName?.trim();
      if (brandName != null && brandName.isNotEmpty) {
        brandId = await _findOrCreateBrand(brandName);
      }

      final productId = draft.productId ?? _uuid.v7();
      final variantId = draft.variantId ?? _uuid.v7();
      final productCreatedAt = draft.productId == null
          ? clock.nowMillis()
          : await existingCreatedAt(db.products, productId) ??
                clock.nowMillis();
      final variantCreatedAt = draft.variantId == null
          ? clock.nowMillis()
          : await existingCreatedAt(db.productVariants, variantId) ??
                clock.nowMillis();

      await writeSyncable<Product>(
        entityTable: 'products',
        table: db.products,
        rowId: productId,
        build: (hlc, now) => Product(
          id: productId,
          createdAt: productCreatedAt,
          updatedAt: now,
          updatedHlc: hlc.pack(),
          name: draft.name,
          description: draft.description,
          brandId: brandId,
          unit: draft.unit,
          isActive: draft.isActive,
          skuRoot: draft.sku,
        ),
      );

      await writeSyncable<ProductVariant>(
        entityTable: 'product_variants',
        table: db.productVariants,
        rowId: variantId,
        build: (hlc, now) => ProductVariant(
          id: variantId,
          createdAt: variantCreatedAt,
          updatedAt: now,
          updatedHlc: hlc.pack(),
          productId: productId,
          sku: draft.sku,
          barcode: draft.barcode,
          name: 'Default',
          priceMinor: draft.price.minorUnits,
          costMinor: draft.cost.minorUnits,
          coreChargeMinor: draft.coreCharge.minorUnits,
          reorderPoint: 0,
          isActive: draft.isActive,
        ),
      );
      return variantId;
    });
  }

  /// Soft-delete (tombstone) a variant so the deletion replicates.
  Future<void> deletePart(String variantId) async {
    final variant =
        await (db.select(db.productVariants)
              ..where((t) => t.id.equals(variantId))
              ..limit(1))
            .getSingleOrNull();
    if (variant == null) return;
    await writeSyncable<ProductVariant>(
      entityTable: 'product_variants',
      table: db.productVariants,
      rowId: variantId,
      op: ChangeOp.delete,
      build: (hlc, now) => variant.copyWith(
        deletedAt: Value(now),
        updatedAt: now,
        updatedHlc: hlc.pack(),
      ),
    );
  }

  Future<String> _findOrCreateBrand(String name) async {
    final existing =
        await (db.select(db.brands)
              ..where((b) => b.name.equals(name) & b.deletedAt.isNull())
              ..limit(1))
            .getSingleOrNull();
    if (existing != null) return existing.id;

    final id = _uuid.v7();
    await writeSyncable<Brand>(
      entityTable: 'brands',
      table: db.brands,
      rowId: id,
      build: (hlc, now) => Brand(
        id: id,
        createdAt: now,
        updatedAt: now,
        updatedHlc: hlc.pack(),
        name: name,
      ),
    );
    return id;
  }

  CatalogItem _toItem(ProductVariant variant, Product product, Brand? brand) {
    return CatalogItem(
      variantId: variant.id,
      productId: product.id,
      sku: variant.sku,
      barcode: variant.barcode,
      productName: product.name,
      variantName: variant.name,
      brandName: brand?.name,
      price: Money(variant.priceMinor),
      cost: Money(variant.costMinor),
      isActive: variant.isActive && product.isActive,
    );
  }
}
