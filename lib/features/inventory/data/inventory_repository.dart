import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../../../core/database/app_database.dart';
import '../../../core/database/sync_repository.dart';
import '../domain/movement_reason.dart';
import '../domain/stock_models.dart';

/// Inventory data. On-hand is the SUM of the append-only [StockMovements]
/// ledger, so it is always consistent and conflict-free after sync (no
/// materialised projection to keep in step).
class InventoryRepository extends SyncRepository {
  final Uuid _uuid;

  InventoryRepository({
    required super.db,
    required super.changeLog,
    required super.hlcService,
    required super.clock,
    Uuid? uuid,
  }) : _uuid = uuid ?? const Uuid();

  // --- Locations ---

  Stream<List<Location>> watchLocations() {
    return (db.select(db.locations)
          ..where((t) => t.deletedAt.isNull())
          ..orderBy([(t) => OrderingTerm.asc(t.name)]))
        .watch();
  }

  Future<String> upsertLocation(LocationDraft draft) async {
    final id = draft.id ?? _uuid.v7();
    final createdAt = draft.id == null
        ? clock.nowMillis()
        : await existingCreatedAt(db.locations, id) ?? clock.nowMillis();
    await writeSyncable<Location>(
      entityTable: 'locations',
      table: db.locations,
      rowId: id,
      build: (hlc, now) => Location(
        id: id,
        createdAt: createdAt,
        updatedAt: now,
        updatedHlc: hlc.pack(),
        name: draft.name,
        type: draft.type,
        isDefault: draft.isDefault,
      ),
    );
    return id;
  }

  /// Returns the default location id, creating a "Main Store" if none exists.
  Future<String> ensureDefaultLocation() async {
    final existing =
        await (db.select(db.locations)
              ..where((t) => t.isDefault.equals(true) & t.deletedAt.isNull())
              ..limit(1))
            .getSingleOrNull();
    if (existing != null) return existing.id;
    return upsertLocation(
      const LocationDraft(name: 'Main Store', isDefault: true),
    );
  }

  // --- Movements & on-hand ---

  /// Append an immutable stock movement (the only way stock changes).
  Future<String> addMovement({
    required String variantId,
    required String locationId,
    required int qty,
    required String reason,
    String? refType,
    String? refId,
    int unitCostMinor = 0,
  }) async {
    final id = _uuid.v7();
    await writeSyncable<StockMovement>(
      entityTable: 'stock_movements',
      table: db.stockMovements,
      rowId: id,
      build: (hlc, now) => StockMovement(
        id: id,
        createdAt: now,
        updatedAt: now,
        updatedHlc: hlc.pack(),
        variantId: variantId,
        locationId: locationId,
        qty: qty,
        reason: reason,
        refType: refType,
        refId: refId,
        unitCostMinor: unitCostMinor,
      ),
    );
    return id;
  }

  /// On-hand for a variant at a location (sum of movements).
  Future<int> onHand(String variantId, String locationId) async {
    final total = db.stockMovements.qty.sum();
    final row =
        await (db.selectOnly(db.stockMovements)
              ..addColumns([total])
              ..where(
                db.stockMovements.variantId.equals(variantId) &
                    db.stockMovements.locationId.equals(locationId) &
                    db.stockMovements.deletedAt.isNull(),
              ))
            .getSingleOrNull();
    return row?.read(total) ?? 0;
  }

  /// Reactive on-hand for a variant across all locations.
  Stream<int> watchOnHandTotal(String variantId) {
    final total = db.stockMovements.qty.sum();
    return (db.selectOnly(db.stockMovements)
          ..addColumns([total])
          ..where(
            db.stockMovements.variantId.equals(variantId) &
                db.stockMovements.deletedAt.isNull(),
          ))
        .watchSingleOrNull()
        .map((row) => row?.read(total) ?? 0);
  }

  /// Adjust on-hand to [targetQty] by appending the difference (used by counts).
  Future<void> adjustTo({
    required String variantId,
    required String locationId,
    required int targetQty,
    String reason = MovementReason.count,
  }) async {
    final current = await onHand(variantId, locationId);
    final delta = targetQty - current;
    if (delta == 0) return;
    await addMovement(
      variantId: variantId,
      locationId: locationId,
      qty: delta,
      reason: reason,
    );
  }

  /// Reactive list of variants with total on-hand, for the inventory screen.
  Stream<List<StockLevel>> watchStockLevels({String query = ''}) {
    final v = db.productVariants;
    final p = db.products;
    final m = db.stockMovements;
    final total = m.qty.sum();

    final statement = db.select(v).join([
      innerJoin(p, p.id.equalsExp(v.productId)),
      leftOuterJoin(m, m.variantId.equalsExp(v.id) & m.deletedAt.isNull()),
    ]);

    var predicate = v.deletedAt.isNull() & p.deletedAt.isNull();
    final trimmed = query.trim();
    if (trimmed.isNotEmpty) {
      final like = '%$trimmed%';
      predicate = predicate & (v.sku.like(like) | p.name.like(like));
    }
    statement
      ..addColumns([total])
      ..where(predicate)
      ..groupBy([v.id])
      ..orderBy([OrderingTerm.asc(p.name)]);

    return statement.watch().map(
      (rows) => rows.map((row) {
        final variant = row.readTable(v);
        final product = row.readTable(p);
        return StockLevel(
          variantId: variant.id,
          sku: variant.sku,
          productName: product.name,
          onHand: row.read(total) ?? 0,
        );
      }).toList(),
    );
  }
}
