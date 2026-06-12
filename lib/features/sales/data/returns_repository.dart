import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../../../core/database/app_database.dart';
import '../../../core/database/sync_repository.dart';
import '../../../core/money/money.dart';
import '../../accounting/data/accounting_repository.dart';
import '../../inventory/data/inventory_repository.dart';
import '../../inventory/domain/movement_reason.dart';

/// Outcome of posting a return.
class ReturnResult {
  final String returnId;
  final String number;
  final Money total;
  const ReturnResult({
    required this.returnId,
    required this.number,
    required this.total,
  });
}

/// A sale line with the quantity still eligible to be returned.
typedef ReturnableLine = ({SaleLine line, int remaining});

/// Posts returns / refunds against completed sales. A return restocks the goods
/// (stock movement, reason `return`) and posts the reversing revenue/PPN/COGS
/// journal. All rows are immutable **events**, so returns union-merge cleanly.
class ReturnsRepository extends SyncRepository {
  final Uuid _uuid;
  final InventoryRepository inventory;
  final AccountingRepository? accounting;

  ReturnsRepository({
    required super.db,
    required super.changeLog,
    required super.hlcService,
    required super.clock,
    required this.inventory,
    this.accounting,
    Uuid? uuid,
  }) : _uuid = uuid ?? const Uuid();

  /// Quantity already returned per sale-line id (across prior returns).
  Future<Map<String, int>> _returnedSoFar(List<String> saleLineIds) async {
    if (saleLineIds.isEmpty) return {};
    final rows =
        await (db.select(db.salesReturnLines)..where(
              (t) => t.saleLineId.isIn(saleLineIds) & t.deletedAt.isNull(),
            ))
            .get();
    final out = <String, int>{};
    for (final r in rows) {
      final id = r.saleLineId;
      if (id != null) out[id] = (out[id] ?? 0) + r.qty;
    }
    return out;
  }

  /// The lines of [saleId] that still have returnable quantity remaining.
  Future<List<ReturnableLine>> returnableLines(String saleId) async {
    final lines = await (db.select(
      db.saleLines,
    )..where((t) => t.saleId.equals(saleId) & t.deletedAt.isNull())).get();
    final returned = await _returnedSoFar(lines.map((l) => l.id).toList());
    return [
      for (final l in lines)
        if (l.qty - (returned[l.id] ?? 0) > 0)
          (line: l, remaining: l.qty - (returned[l.id] ?? 0)),
    ];
  }

  Future<List<SalesReturn>> returnsForSale(String saleId) {
    return (db.select(db.salesReturns)
          ..where((t) => t.saleId.equals(saleId) & t.deletedAt.isNull())
          ..orderBy([(t) => OrderingTerm.desc(t.createdAt)]))
        .get();
  }

  /// Voids a sale: returns every remaining line quantity in one pass,
  /// refunding to the original tender (cash payments → cash, anything else →
  /// bank). Throws if the sale has nothing left to void (already fully
  /// returned/voided).
  Future<ReturnResult> voidSale(String saleId, {String? reason}) async {
    final remaining = await returnableLines(saleId);
    if (remaining.isEmpty) {
      throw StateError('Nothing left to void on this sale');
    }
    final payment =
        await (db.select(db.payments)
              ..where((t) => t.saleId.equals(saleId) & t.deletedAt.isNull())
              ..limit(1))
            .getSingleOrNull();
    final refundMethod = (payment == null || payment.method == 'cash')
        ? 'cash'
        : 'bank';
    return createReturn(
      saleId: saleId,
      quantitiesBySaleLineId: {
        for (final l in remaining) l.line.id: l.remaining,
      },
      refundMethod: refundMethod,
      reason: reason ?? 'void',
    );
  }

  /// Returns goods from [saleId]. [quantitiesBySaleLineId] maps a sale-line id
  /// to the quantity returned (1..remaining). Refund is paid from cash/bank.
  Future<ReturnResult> createReturn({
    required String saleId,
    required Map<String, int> quantitiesBySaleLineId,
    String refundMethod = 'cash',
    String? reason,
  }) async {
    final sale =
        await (db.select(db.sales)
              ..where((t) => t.id.equals(saleId))
              ..limit(1))
            .getSingleOrNull();
    if (sale == null) throw StateError('Sale not found: $saleId');
    final saleLines = await (db.select(
      db.saleLines,
    )..where((t) => t.saleId.equals(saleId) & t.deletedAt.isNull())).get();
    final byId = {for (final l in saleLines) l.id: l};
    final returnedSoFar = await _returnedSoFar(byId.keys.toList());

    final picks =
        <({SaleLine line, int qty, int lineTotal, int tax, int cost})>[];
    var total = 0, ppn = 0, cogs = 0;
    quantitiesBySaleLineId.forEach((lineId, qty) {
      if (qty <= 0) return;
      final l = byId[lineId];
      if (l == null) throw StateError('Sale line not found: $lineId');
      final remaining = l.qty - (returnedSoFar[lineId] ?? 0);
      if (qty > remaining) {
        throw StateError(
          'Return exceeds remaining quantity for "${l.description}"',
        );
      }
      // Prorate the line's stored total/tax by the returned fraction.
      final lineTotal = ((l.lineTotalMinor * qty) / l.qty).round();
      final tax = ((l.taxMinor * qty) / l.qty).round();
      final cost = l.unitCostMinor * qty;
      total += lineTotal;
      ppn += tax;
      cogs += cost;
      picks.add((
        line: l,
        qty: qty,
        lineTotal: lineTotal,
        tax: tax,
        cost: cost,
      ));
    });
    if (picks.isEmpty) throw StateError('Nothing to return');
    final dpp = total - ppn;

    return db.transaction(() async {
      final returnId = _uuid.v7();
      final now = clock.nowMillis();
      final number = await _nextReturnNumber();

      await writeSyncable<SalesReturn>(
        entityTable: 'sales_returns',
        table: db.salesReturns,
        rowId: returnId,
        build: (hlc, n) => SalesReturn(
          id: returnId,
          createdAt: now,
          updatedAt: n,
          updatedHlc: hlc.pack(),
          number: number,
          saleId: saleId,
          locationId: sale.locationId,
          refundMethod: refundMethod,
          reason: reason,
          subtotalMinor: dpp,
          taxTotalMinor: ppn,
          totalMinor: total,
        ),
      );

      for (final p in picks) {
        final rlId = _uuid.v7();
        await writeSyncable<SalesReturnLine>(
          entityTable: 'sales_return_lines',
          table: db.salesReturnLines,
          rowId: rlId,
          build: (hlc, n) => SalesReturnLine(
            id: rlId,
            createdAt: now,
            updatedAt: n,
            updatedHlc: hlc.pack(),
            returnId: returnId,
            saleLineId: p.line.id,
            variantId: p.line.variantId,
            description: p.line.description,
            qty: p.qty,
            unitPriceMinor: p.line.unitPriceMinor,
            taxMinor: p.tax,
            lineTotalMinor: p.lineTotal,
            unitCostMinor: p.line.unitCostMinor,
          ),
        );
        if (p.line.variantId != null) {
          await inventory.addMovement(
            variantId: p.line.variantId!,
            locationId: sale.locationId,
            qty: p.qty, // positive: goods come back in
            reason: MovementReason.customerReturn,
            refType: 'sales_return',
            refId: returnId,
            unitCostMinor: p.line.unitCostMinor,
          );
        }
      }

      await accounting?.postReturnJournal(
        returnId: returnId,
        date: now,
        method: refundMethod,
        totalMinor: total,
        dppMinor: dpp,
        ppnMinor: ppn,
        cogsMinor: cogs,
      );

      return ReturnResult(
        returnId: returnId,
        number: number,
        total: Money(total),
      );
    });
  }

  Future<String> _nextReturnNumber() async {
    const key = 'seq.return';
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
    return 'CR-${next.toString().padLeft(6, '0')}';
  }
}
