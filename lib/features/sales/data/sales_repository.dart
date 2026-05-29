import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../../../core/database/app_database.dart';
import '../../../core/database/sync_repository.dart';
import '../../../core/money/money.dart';
import '../../inventory/data/inventory_repository.dart';
import '../../inventory/domain/movement_reason.dart';
import '../domain/cart.dart';

/// Writes completed sales. A sale, its lines, its payment and the corresponding
/// stock movements are all appended in one transaction — every row immutable and
/// conflict-free across devices.
class SalesRepository extends SyncRepository {
  final Uuid _uuid;
  final InventoryRepository inventory;

  SalesRepository({
    required super.db,
    required super.changeLog,
    required super.hlcService,
    required super.clock,
    required this.inventory,
    Uuid? uuid,
  }) : _uuid = uuid ?? const Uuid();

  Future<SaleResult> completeSale({
    required List<CartLine> lines,
    required String locationId,
    required Money tendered,
    String? customerId,
    String method = 'cash',
  }) async {
    if (lines.isEmpty) {
      throw StateError('Cannot complete an empty sale');
    }
    return db.transaction(() async {
      final saleId = _uuid.v7();
      final now = clock.nowMillis();
      final number = await _nextSaleNumber();

      final subtotal = Money.sum(lines.map((l) => l.gross));
      final discount = Money.sum(lines.map((l) => l.discount));
      final total = subtotal - discount;

      await writeSyncable<Sale>(
        entityTable: 'sales',
        table: db.sales,
        rowId: saleId,
        build: (hlc, n) => Sale(
          id: saleId,
          createdAt: now,
          updatedAt: n,
          updatedHlc: hlc.pack(),
          number: number,
          customerId: customerId,
          locationId: locationId,
          status: 'completed',
          subtotalMinor: subtotal.minorUnits,
          discountMinor: discount.minorUnits,
          taxTotalMinor: 0,
          totalMinor: total.minorUnits,
          paidTotalMinor: total.minorUnits,
          postedAt: now,
        ),
      );

      for (final line in lines) {
        final lineId = _uuid.v7();
        await writeSyncable<SaleLine>(
          entityTable: 'sale_lines',
          table: db.saleLines,
          rowId: lineId,
          build: (hlc, n) => SaleLine(
            id: lineId,
            createdAt: now,
            updatedAt: n,
            updatedHlc: hlc.pack(),
            saleId: saleId,
            variantId: line.variantId,
            description: line.name,
            qty: line.qty,
            unitPriceMinor: line.unitPrice.minorUnits,
            discountMinor: line.discount.minorUnits,
            taxMinor: 0,
            lineTotalMinor: line.total.minorUnits,
            unitCostMinor: line.unitCost.minorUnits,
          ),
        );
        // Deduct stock as a sale movement (append-only ledger).
        await inventory.addMovement(
          variantId: line.variantId,
          locationId: locationId,
          qty: -line.qty,
          reason: MovementReason.sale,
          refType: 'sale',
          refId: saleId,
          unitCostMinor: line.unitCost.minorUnits,
        );
      }

      final change = tendered - total;
      final paymentId = _uuid.v7();
      await writeSyncable<Payment>(
        entityTable: 'payments',
        table: db.payments,
        rowId: paymentId,
        build: (hlc, n) => Payment(
          id: paymentId,
          createdAt: now,
          updatedAt: n,
          updatedHlc: hlc.pack(),
          saleId: saleId,
          method: method,
          amountMinor: total.minorUnits,
          tenderedMinor: tendered.minorUnits,
          changeMinor: change.isNegative ? 0 : change.minorUnits,
        ),
      );

      return SaleResult(
        saleId: saleId,
        number: number,
        total: total,
        change: change.isNegative ? const Money(0) : change,
      );
    });
  }

  Stream<List<Sale>> watchRecentSales({int limit = 50}) {
    return (db.select(db.sales)
          ..where((t) => t.deletedAt.isNull())
          ..orderBy([(t) => OrderingTerm.desc(t.createdAt)])
          ..limit(limit))
        .watch();
  }

  Future<List<SaleLine>> linesForSale(String saleId) {
    return (db.select(
      db.saleLines,
    )..where((t) => t.saleId.equals(saleId) & t.deletedAt.isNull())).get();
  }

  /// Per-device sale number sequence (stored locally in sync_meta).
  Future<String> _nextSaleNumber() async {
    const key = 'seq.sale';
    final row =
        await (db.select(db.syncMeta)
              ..where((t) => t.key.equals(key))
              ..limit(1))
            .getSingleOrNull();
    final next = (int.tryParse(row?.value ?? '0') ?? 0) + 1;
    await db
        .into(db.syncMeta)
        .insertOnConflictUpdate(
          SyncMetaCompanion.insert(key: key, value: next.toString()),
        );
    return 'S-${next.toString().padLeft(6, '0')}';
  }
}
