import 'package:drift/drift.dart';

import '../syncable_table.dart';

// NOTE: Synced tables intentionally declare **no** foreign-key or unique
// constraints. Rows can arrive out of order during sync (a variant before its
// product) and two offline devices could mint the same SKU; DB-level
// constraints would reject those. Referential integrity and SKU uniqueness are
// enforced/validated in the repository layer instead. Indexes below are for
// search performance only.

/// Manufacturer / brand. Master data (LWW).
class Brands extends Table with SyncableTable {
  TextColumn get name => text()();
  TextColumn get code => text().nullable()();
}

/// Product category tree (parentId is a self reference, app-enforced).
class Categories extends Table with SyncableTable {
  TextColumn get name => text()();
  TextColumn get parentId => text().nullable()();
}

/// A part/product. One product has one or more [ProductVariants].
class Products extends Table with SyncableTable {
  TextColumn get skuRoot => text().nullable()();
  TextColumn get name => text()();
  TextColumn get description => text().nullable()();
  TextColumn get brandId => text().nullable()();
  TextColumn get categoryId => text().nullable()();
  TextColumn get unit => text().withDefault(const Constant('each'))();
  TextColumn get taxRateId => text().nullable()();
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();
}

/// A sellable/stockable variant (the unit that carries SKU, barcode, price,
/// cost and core charge). Money fields are integer minor units.
@TableIndex(name: 'idx_variant_product', columns: {#productId})
@TableIndex(name: 'idx_variant_sku', columns: {#sku})
@TableIndex(name: 'idx_variant_barcode', columns: {#barcode})
class ProductVariants extends Table with SyncableTable {
  TextColumn get productId => text()();
  TextColumn get sku => text()();
  TextColumn get barcode => text().nullable()();
  TextColumn get name => text().withDefault(const Constant('Default'))();
  IntColumn get priceMinor => integer().withDefault(const Constant(0))();
  IntColumn get costMinor => integer().withDefault(const Constant(0))();
  IntColumn get coreChargeMinor => integer().withDefault(const Constant(0))();
  IntColumn get reorderPoint => integer().withDefault(const Constant(0))();
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();
}

// --- Automotive-specific catalog data ---

/// A vehicle (Year/Make/Model/Engine) used for fitment lookup. Master data.
class Vehicles extends Table with SyncableTable {
  TextColumn get make => text()();
  TextColumn get model => text()();
  IntColumn get yearFrom => integer().nullable()();
  IntColumn get yearTo => integer().nullable()();
  TextColumn get engine => text().nullable()();
  TextColumn get body => text().nullable()();
}

/// Many-to-many link: a variant fits a vehicle. Master data.
@TableIndex(name: 'idx_fitment_variant', columns: {#variantId})
@TableIndex(name: 'idx_fitment_vehicle', columns: {#vehicleId})
class Fitments extends Table with SyncableTable {
  TextColumn get variantId => text()();
  TextColumn get vehicleId => text()();
  TextColumn get note => text().nullable()();
}

/// Cross-reference / interchange numbers (OEM or aftermarket) for a variant.
@TableIndex(name: 'idx_xref_variant', columns: {#variantId})
@TableIndex(name: 'idx_xref_number', columns: {#otherNumber})
class CrossReferences extends Table with SyncableTable {
  TextColumn get variantId => text()();
  TextColumn get otherNumber => text()();
  TextColumn get otherBrand => text().nullable()();

  /// 'oem' | 'interchange'.
  TextColumn get refType => text().withDefault(const Constant('interchange'))();
}

/// Supersession: [oldVariantId] is replaced by [newVariantId]. Master data.
@TableIndex(name: 'idx_supersession_old', columns: {#oldVariantId})
class Supersessions extends Table with SyncableTable {
  TextColumn get oldVariantId => text()();
  TextColumn get newVariantId => text()();
  TextColumn get reason => text().nullable()();
}
