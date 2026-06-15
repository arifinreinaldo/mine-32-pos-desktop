import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../../../core/database/app_database.dart';
import '../../../core/database/sync_repository.dart';
import '../../../core/sync/change_record.dart';
import '../../accounting/data/accounting_repository.dart';
import '../../inventory/data/inventory_repository.dart';
import '../../inventory/domain/movement_reason.dart';
import '../domain/purchasing_models.dart';

/// Suppliers + purchase orders. Receiving a PO appends stock movements and posts
/// the goods-receipt journal (Dr Inventory / Cr Accounts Payable), atomically.
class PurchasingRepository extends SyncRepository {
  final Uuid _uuid;
  final InventoryRepository inventory;
  final AccountingRepository accounting;

  PurchasingRepository({
    required super.db,
    required super.changeLog,
    required super.hlcService,
    required super.clock,
    required this.inventory,
    required this.accounting,
    Uuid? uuid,
  }) : _uuid = uuid ?? const Uuid();

  // --- Suppliers ---

  Stream<List<Supplier>> watchSuppliers({String query = ''}) {
    final s = db.suppliers;
    final statement = db.select(s)..where((t) => t.deletedAt.isNull());
    final trimmed = query.trim();
    if (trimmed.isNotEmpty) {
      final like = '%$trimmed%';
      statement.where((t) => t.name.like(like) | t.phone.like(like));
    }
    statement.orderBy([(t) => OrderingTerm.asc(t.name)]);
    return statement.watch();
  }

  Future<Supplier?> getSupplier(String id) {
    return (db.select(db.suppliers)
          ..where((t) => t.id.equals(id))
          ..limit(1))
        .getSingleOrNull();
  }

  Future<String> saveSupplier(SupplierDraft draft) async {
    final id = draft.id ?? _uuid.v7();
    final createdAt = draft.id == null
        ? clock.nowMillis()
        : await existingCreatedAt(db.suppliers, id) ?? clock.nowMillis();
    await writeSyncable<Supplier>(
      entityTable: 'suppliers',
      table: db.suppliers,
      rowId: id,
      build: (hlc, now) => Supplier(
        id: id,
        createdAt: createdAt,
        updatedAt: now,
        updatedHlc: hlc.pack(),
        name: draft.name,
        phone: draft.phone,
        email: draft.email,
        taxNumber: draft.npwp,
        address: draft.address,
        terms: draft.terms,
        notes: draft.notes,
      ),
    );
    return id;
  }

  Future<void> deleteSupplier(String id) async {
    final row = await getSupplier(id);
    if (row == null) return;
    await writeSyncable<Supplier>(
      entityTable: 'suppliers',
      table: db.suppliers,
      rowId: id,
      op: ChangeOp.delete,
      build: (hlc, now) => row.copyWith(
        deletedAt: Value(now),
        updatedAt: now,
        updatedHlc: hlc.pack(),
      ),
    );
  }

  /// Outstanding payable to a supplier: received-PO balances minus payments.
  Future<int> apBalance(String supplierId) async {
    final p = db.purchaseOrders;
    final outstanding = (p.totalMinor - p.paidTotalMinor).sum();
    final poRow =
        await (db.selectOnly(p)
              ..addColumns([outstanding])
              ..where(
                p.supplierId.equals(supplierId) &
                    p.deletedAt.isNull() &
                    p.status.equals('received'),
              ))
            .getSingleOrNull();
    final fromPos = poRow?.read(outstanding) ?? 0;

    final sp = db.supplierPayments;
    final paySum = sp.amountMinor.sum();
    final payRow =
        await (db.selectOnly(sp)
              ..addColumns([paySum])
              ..where(sp.supplierId.equals(supplierId) & sp.deletedAt.isNull()))
            .getSingleOrNull();
    final paid = payRow?.read(paySum) ?? 0;

    return fromPos - paid;
  }

  /// Record a payment to a supplier against AP and post Dr AP / Cr Cash.
  Future<String> paySupplier({
    required String supplierId,
    required int amountMinor,
    String method = 'cash',
    String? reference,
  }) async {
    final id = _uuid.v7();
    await db.transaction(() async {
      await writeSyncable<SupplierPayment>(
        entityTable: 'supplier_payments',
        table: db.supplierPayments,
        rowId: id,
        build: (hlc, now) => SupplierPayment(
          id: id,
          createdAt: now,
          updatedAt: now,
          updatedHlc: hlc.pack(),
          supplierId: supplierId,
          amountMinor: amountMinor,
          method: method,
          reference: reference,
        ),
      );
      await accounting.postSupplierPaymentJournal(
        refId: id,
        date: clock.nowMillis(),
        amountMinor: amountMinor,
        method: method,
      );
    });
    return id;
  }

  // --- Purchase orders ---

  Stream<List<PurchaseOrder>> watchPurchaseOrders({int limit = 100}) {
    return (db.select(db.purchaseOrders)
          ..where((t) => t.deletedAt.isNull())
          ..orderBy([(t) => OrderingTerm.desc(t.createdAt)])
          ..limit(limit))
        .watch();
  }

  Future<PurchaseOrder?> getPurchaseOrder(String id) {
    return (db.select(db.purchaseOrders)
          ..where((t) => t.id.equals(id))
          ..limit(1))
        .getSingleOrNull();
  }

  Future<List<PurchaseOrderLine>> linesForPo(String poId) {
    return (db.select(
      db.purchaseOrderLines,
    )..where((t) => t.poId.equals(poId) & t.deletedAt.isNull())).get();
  }

  /// Units on the way per variant: the outstanding (ordered − received)
  /// quantity across open POs (status ordered/draft). Reactive — the inventory
  /// screen shows it next to on-hand so reorder decisions account for stock in
  /// transit.
  Stream<Map<String, int>> watchIncomingByVariant() {
    final pol = db.purchaseOrderLines;
    final po = db.purchaseOrders;
    final remaining = (pol.qtyOrdered - pol.qtyReceived).sum();
    final statement =
        db.select(pol).join([innerJoin(po, po.id.equalsExp(pol.poId))])
          ..addColumns([remaining, pol.variantId])
          ..where(
            pol.deletedAt.isNull() &
                po.deletedAt.isNull() &
                po.status.isIn(['ordered', 'draft']),
          )
          ..groupBy([pol.variantId]);
    return statement.watch().map((rows) {
      final out = <String, int>{};
      for (final r in rows) {
        final variantId = r.read(pol.variantId);
        final qty = r.read(remaining) ?? 0;
        if (variantId != null && qty > 0) out[variantId] = qty;
      }
      return out;
    });
  }

  Future<String> createPurchaseOrder({
    required String supplierId,
    required String locationId,
    required List<PoLineInput> lines,
    String? notes,
  }) async {
    return db.transaction(() async {
      final poId = _uuid.v7();
      final now = clock.nowMillis();
      final number = await _nextPoNumber();
      final total = lines.fold(0, (s, l) => s + l.qty * l.unitCostMinor);

      await writeSyncable<PurchaseOrder>(
        entityTable: 'purchase_orders',
        table: db.purchaseOrders,
        rowId: poId,
        build: (hlc, n) => PurchaseOrder(
          id: poId,
          createdAt: now,
          updatedAt: n,
          updatedHlc: hlc.pack(),
          number: number,
          supplierId: supplierId,
          locationId: locationId,
          status: 'ordered',
          totalMinor: total,
          paidTotalMinor: 0,
          orderedAt: now,
          notes: notes,
        ),
      );

      for (final l in lines) {
        final lineId = _uuid.v7();
        await writeSyncable<PurchaseOrderLine>(
          entityTable: 'purchase_order_lines',
          table: db.purchaseOrderLines,
          rowId: lineId,
          build: (hlc, n) => PurchaseOrderLine(
            id: lineId,
            createdAt: now,
            updatedAt: n,
            updatedHlc: hlc.pack(),
            poId: poId,
            variantId: l.variantId,
            description: l.description,
            qtyOrdered: l.qty,
            qtyReceived: 0,
            unitCostMinor: l.unitCostMinor,
            lineTotalMinor: l.qty * l.unitCostMinor,
          ),
        );
      }
      return poId;
    });
  }

  /// Receive all outstanding quantity on a PO: append +stock movements, mark the
  /// lines/PO received, and post the goods-receipt journal. Idempotent per PO
  /// (does nothing if already received).
  Future<void> receivePurchaseOrder(String poId) async {
    await db.transaction(() async {
      final po = await getPurchaseOrder(poId);
      if (po == null || po.status == 'received') return;
      final lines = await linesForPo(poId);
      final now = clock.nowMillis();
      var totalCost = 0;

      for (final l in lines) {
        await inventory.addMovement(
          variantId: l.variantId,
          locationId: po.locationId,
          qty: l.qtyOrdered,
          reason: MovementReason.purchase,
          refType: 'purchase_order',
          refId: poId,
          unitCostMinor: l.unitCostMinor,
        );
        await writeSyncable<PurchaseOrderLine>(
          entityTable: 'purchase_order_lines',
          table: db.purchaseOrderLines,
          rowId: l.id,
          build: (hlc, n) => l.copyWith(
            qtyReceived: l.qtyOrdered,
            updatedAt: n,
            updatedHlc: hlc.pack(),
          ),
        );
        totalCost += l.qtyOrdered * l.unitCostMinor;
      }

      await writeSyncable<PurchaseOrder>(
        entityTable: 'purchase_orders',
        table: db.purchaseOrders,
        rowId: poId,
        build: (hlc, n) => po.copyWith(
          status: 'received',
          receivedAt: Value(now),
          updatedAt: n,
          updatedHlc: hlc.pack(),
        ),
      );

      await accounting.postPurchaseJournal(
        poId: poId,
        date: now,
        totalMinor: totalCost,
      );
    });
  }

  Future<String> _nextPoNumber() async {
    const key = 'seq.po';
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
    return 'PO-${next.toString().padLeft(6, '0')}';
  }
}
