import '../../../core/database/app_database.dart';
import '../../../core/sync/sync_entity.dart';

/// Registers catalog tables with the sync engine. All catalog data is mutable
/// master data, so conflicts resolve last-write-wins by HLC.
void registerCatalogSyncEntities(SyncRegistry registry) {
  registry.register(
    SyncEntity<Brand>(
      name: 'brands',
      kind: SyncKind.master,
      tableOf: (db) => db.brands,
      fromJson: Brand.fromJson,
    ),
  );
  registry.register(
    SyncEntity<Category>(
      name: 'categories',
      kind: SyncKind.master,
      tableOf: (db) => db.categories,
      fromJson: Category.fromJson,
    ),
  );
  registry.register(
    SyncEntity<Product>(
      name: 'products',
      kind: SyncKind.master,
      tableOf: (db) => db.products,
      fromJson: Product.fromJson,
    ),
  );
  registry.register(
    SyncEntity<ProductVariant>(
      name: 'product_variants',
      kind: SyncKind.master,
      tableOf: (db) => db.productVariants,
      fromJson: ProductVariant.fromJson,
    ),
  );
  // Automotive catalog
  registry.register(
    SyncEntity<Vehicle>(
      name: 'vehicles',
      kind: SyncKind.master,
      tableOf: (db) => db.vehicles,
      fromJson: Vehicle.fromJson,
    ),
  );
  registry.register(
    SyncEntity<Fitment>(
      name: 'fitments',
      kind: SyncKind.master,
      tableOf: (db) => db.fitments,
      fromJson: Fitment.fromJson,
    ),
  );
  registry.register(
    SyncEntity<CrossReference>(
      name: 'cross_references',
      kind: SyncKind.master,
      tableOf: (db) => db.crossReferences,
      fromJson: CrossReference.fromJson,
    ),
  );
  registry.register(
    SyncEntity<Supersession>(
      name: 'supersessions',
      kind: SyncKind.master,
      tableOf: (db) => db.supersessions,
      fromJson: Supersession.fromJson,
    ),
  );
}
