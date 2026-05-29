import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../../../core/database/app_database.dart';
import '../../../core/database/sync_repository.dart';
import '../../../core/sync/change_record.dart';
import '../domain/auto_parts_models.dart';

/// Automotive catalog data: vehicles, fitment (which vehicles a part fits),
/// cross-reference/interchange numbers, and supersession chains. All replicate
/// as master data via [SyncRepository].
class AutoPartsRepository extends SyncRepository {
  final Uuid _uuid;

  AutoPartsRepository({
    required super.db,
    required super.changeLog,
    required super.hlcService,
    required super.clock,
    Uuid? uuid,
  }) : _uuid = uuid ?? const Uuid();

  // --- Vehicles ---

  Future<String> upsertVehicle(VehicleDraft draft) async {
    final id = draft.id ?? _uuid.v7();
    final createdAt = draft.id == null
        ? clock.nowMillis()
        : await existingCreatedAt(db.vehicles, id) ?? clock.nowMillis();
    await writeSyncable<Vehicle>(
      entityTable: 'vehicles',
      table: db.vehicles,
      rowId: id,
      build: (hlc, now) => Vehicle(
        id: id,
        createdAt: createdAt,
        updatedAt: now,
        updatedHlc: hlc.pack(),
        make: draft.make,
        model: draft.model,
        yearFrom: draft.yearFrom,
        yearTo: draft.yearTo,
        engine: draft.engine,
        body: draft.body,
      ),
    );
    return id;
  }

  // --- Fitment ---

  Future<String> addFitment({
    required String variantId,
    required String vehicleId,
    String? note,
  }) async {
    final id = _uuid.v7();
    await writeSyncable<Fitment>(
      entityTable: 'fitments',
      table: db.fitments,
      rowId: id,
      build: (hlc, now) => Fitment(
        id: id,
        createdAt: now,
        updatedAt: now,
        updatedHlc: hlc.pack(),
        variantId: variantId,
        vehicleId: vehicleId,
        note: note,
      ),
    );
    return id;
  }

  Stream<List<FitmentView>> watchFitments(String variantId) {
    final f = db.fitments;
    final v = db.vehicles;
    final statement =
        db.select(f).join([innerJoin(v, v.id.equalsExp(f.vehicleId))])..where(
          f.variantId.equals(variantId) &
              f.deletedAt.isNull() &
              v.deletedAt.isNull(),
        );
    return statement.watch().map(
      (rows) => rows.map((row) {
        final fit = row.readTable(f);
        final veh = row.readTable(v);
        return FitmentView(
          fitmentId: fit.id,
          vehicleId: veh.id,
          vehicleLabel: vehicleLabel(veh),
          note: fit.note,
        );
      }).toList(),
    );
  }

  Future<void> removeFitment(String id) => _tombstoneFitment(id);

  Future<void> _tombstoneFitment(String id) async {
    final row =
        await (db.select(db.fitments)
              ..where((t) => t.id.equals(id))
              ..limit(1))
            .getSingleOrNull();
    if (row == null) return;
    await writeSyncable<Fitment>(
      entityTable: 'fitments',
      table: db.fitments,
      rowId: id,
      op: ChangeOp.delete,
      build: (hlc, now) => row.copyWith(
        deletedAt: Value(now),
        updatedAt: now,
        updatedHlc: hlc.pack(),
      ),
    );
  }

  // --- Cross references ---

  Future<String> addCrossReference({
    required String variantId,
    required String otherNumber,
    String? otherBrand,
    String refType = 'interchange',
  }) async {
    final id = _uuid.v7();
    await writeSyncable<CrossReference>(
      entityTable: 'cross_references',
      table: db.crossReferences,
      rowId: id,
      build: (hlc, now) => CrossReference(
        id: id,
        createdAt: now,
        updatedAt: now,
        updatedHlc: hlc.pack(),
        variantId: variantId,
        otherNumber: otherNumber,
        otherBrand: otherBrand,
        refType: refType,
      ),
    );
    return id;
  }

  Stream<List<CrossReferenceView>> watchCrossReferences(String variantId) {
    return (db.select(db.crossReferences)
          ..where((t) => t.variantId.equals(variantId) & t.deletedAt.isNull()))
        .watch()
        .map(
          (rows) => rows
              .map(
                (r) => CrossReferenceView(
                  id: r.id,
                  otherNumber: r.otherNumber,
                  otherBrand: r.otherBrand,
                  refType: r.refType,
                ),
              )
              .toList(),
        );
  }

  // --- Supersession ---

  Future<String> addSupersession({
    required String oldVariantId,
    required String newVariantId,
    String? reason,
  }) async {
    final id = _uuid.v7();
    await writeSyncable<Supersession>(
      entityTable: 'supersessions',
      table: db.supersessions,
      rowId: id,
      build: (hlc, now) => Supersession(
        id: id,
        createdAt: now,
        updatedAt: now,
        updatedHlc: hlc.pack(),
        oldVariantId: oldVariantId,
        newVariantId: newVariantId,
        reason: reason,
      ),
    );
    return id;
  }

  /// The counter lookup: variant ids matching [number] by SKU, barcode, or any
  /// cross-reference/interchange number. The whole point of an auto-parts POS.
  Future<Set<String>> lookupVariantIdsByNumber(String number) async {
    final like = '%${number.trim()}%';
    final bySku =
        await (db.select(db.productVariants)..where(
              (t) =>
                  (t.sku.like(like) | t.barcode.like(like)) &
                  t.deletedAt.isNull(),
            ))
            .get();
    final byXref = await (db.select(
      db.crossReferences,
    )..where((t) => t.otherNumber.like(like) & t.deletedAt.isNull())).get();
    return {...bySku.map((v) => v.id), ...byXref.map((x) => x.variantId)};
  }

  static String vehicleLabel(Vehicle v) {
    final years = (v.yearFrom != null || v.yearTo != null)
        ? ' ${v.yearFrom ?? ''}-${v.yearTo ?? ''}'
        : '';
    final engine = (v.engine != null && v.engine!.isNotEmpty)
        ? ' ${v.engine}'
        : '';
    return '${v.make} ${v.model}$years$engine'.trim();
  }
}
