import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../../../core/database/app_database.dart';
import '../../../core/database/sync_repository.dart';
import '../../../core/money/money.dart';
import '../../accounting/data/accounting_repository.dart';
import '../../accounting/domain/tax_math.dart';
import '../../inventory/data/inventory_repository.dart';
import '../../inventory/domain/movement_reason.dart';
import '../domain/cart.dart';

/// Writes completed sales. A sale, its lines, its payment, the stock movements
/// and (optionally) the accounting journal are all appended in one transaction —
/// every row immutable and conflict-free across devices.
class SalesRepository extends SyncRepository {
  final Uuid _uuid;
  final InventoryRepository inventory;

  /// When provided, a balanced sale journal (revenue, PPN, COGS) is posted.
  final AccountingRepository? accounting;

  SalesRepository({
    required super.db,
    required super.changeLog,
    required super.hlcService,
    required super.clock,
    required this.inventory,
    this.accounting,
    Uuid? uuid,
  }) : _uuid = uuid ?? const Uuid();

  /// Completes a sale. If [taxBasisPoints] > 0, each line is split into tax base
  /// (DPP) and tax (PPN); [taxInclusive] controls whether listed prices already
  /// include the tax (the Indonesian retail default).
  Future<SaleResult> completeSale({
    required List<CartLine> lines,
    required String locationId,
    required Money tendered,
    String? customerId,
    String method = 'cash',
    int taxBasisPoints = 0,
    bool taxInclusive = true,
    String? buyerName,
    String? buyerNpwp,
    String? fakturNumber,
  }) async {
    if (lines.isEmpty) {
      throw StateError('Cannot complete an empty sale');
    }
    return db.transaction(() async {
      final saleId = _uuid.v7();
      final now = clock.nowMillis();
      final number = await _nextSaleNumber();

      var dppMinor = 0;
      var ppnMinor = 0;
      var totalMinor = 0;
      var discountMinor = 0;
      var cogsMinor = 0;
      final calcs = <({CartLine line, int taxMinor, int lineTotalMinor})>[];

      for (final line in lines) {
        final payable = (line.gross - line.discount).minorUnits;
        final amounts = TaxMath.split(
          amountMinor: payable,
          basisPoints: taxBasisPoints,
          inclusive: taxInclusive,
        );
        dppMinor += amounts.baseMinor;
        ppnMinor += amounts.taxMinor;
        totalMinor += amounts.totalMinor;
        discountMinor += line.discount.minorUnits;
        cogsMinor += line.unitCost.minorUnits * line.qty;
        calcs.add((
          line: line,
          taxMinor: amounts.taxMinor,
          lineTotalMinor: amounts.totalMinor,
        ));
      }

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
          subtotalMinor: dppMinor,
          discountMinor: discountMinor,
          taxTotalMinor: ppnMinor,
          totalMinor: totalMinor,
          paidTotalMinor: totalMinor,
          postedAt: now,
          buyerName: buyerName,
          buyerNpwp: buyerNpwp,
          fakturNumber: fakturNumber,
        ),
      );

      for (final calc in calcs) {
        final line = calc.line;
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
            taxMinor: calc.taxMinor,
            lineTotalMinor: calc.lineTotalMinor,
            unitCostMinor: line.unitCost.minorUnits,
          ),
        );
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

      final tenderedMinor = tendered.minorUnits;
      final changeMinor = tenderedMinor - totalMinor;
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
          amountMinor: totalMinor,
          tenderedMinor: tenderedMinor,
          changeMinor: changeMinor < 0 ? 0 : changeMinor,
        ),
      );

      // Post the accounting journal (revenue, PPN, COGS) if wired.
      await accounting?.postSaleJournal(
        saleId: saleId,
        date: now,
        method: method,
        totalMinor: totalMinor,
        dppMinor: dppMinor,
        ppnMinor: ppnMinor,
        cogsMinor: cogsMinor,
      );

      return SaleResult(
        saleId: saleId,
        number: number,
        total: Money(totalMinor),
        change: Money(changeMinor < 0 ? 0 : changeMinor),
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

  Future<Sale?> getSale(String saleId) {
    return (db.select(db.sales)
          ..where((t) => t.id.equals(saleId))
          ..limit(1))
        .getSingleOrNull();
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
