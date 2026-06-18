import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../../../core/database/app_database.dart';
import '../../../core/database/sync_repository.dart';
import '../../../core/sync/change_record.dart';
import '../../accounting/data/accounting_repository.dart';
import '../../accounting/domain/tax_math.dart';
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

  /// Outstanding payable to a supplier: the value of goods actually received
  /// (Σ qtyReceived × unitCost, so partial receipts count their received part)
  /// minus payments.
  Future<int> apBalance(String supplierId) async {
    final pol = db.purchaseOrderLines;
    final po = db.purchaseOrders;
    final received = (pol.qtyReceived * pol.unitCostMinor).sum();
    final poRow =
        await (db.selectOnly(pol).join([
                innerJoin(po, po.id.equalsExp(pol.poId)),
              ])
              ..addColumns([received])
              ..where(
                po.supplierId.equals(supplierId) &
                    po.deletedAt.isNull() &
                    pol.deletedAt.isNull(),
              ))
            .getSingleOrNull();
    final fromPos = poRow?.read(received) ?? 0;

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

  /// Purchase orders for a supplier with goods received but not yet fully paid
  /// (received value − allocated payments > 0), oldest first.
  Future<List<({PurchaseOrder po, int outstanding})>> openPurchaseOrders(
    String supplierId,
  ) async {
    final pos =
        await (db.select(db.purchaseOrders)
              ..where(
                (t) => t.supplierId.equals(supplierId) & t.deletedAt.isNull(),
              )
              ..orderBy([(t) => OrderingTerm.asc(t.createdAt)]))
            .get();
    final payments =
        await (db.select(db.supplierPayments)..where(
              (t) =>
                  t.supplierId.equals(supplierId) &
                  t.deletedAt.isNull() &
                  t.poId.isNotNull(),
            ))
            .get();
    final allocated = <String, int>{};
    for (final p in payments) {
      final pid = p.poId;
      if (pid != null) allocated[pid] = (allocated[pid] ?? 0) + p.amountMinor;
    }
    final out = <({PurchaseOrder po, int outstanding})>[];
    for (final po in pos) {
      final lines = await linesForPo(po.id);
      final received = lines.fold(
        0,
        (s, l) => s + l.qtyReceived * l.unitCostMinor,
      );
      final outstanding = received - (allocated[po.id] ?? 0);
      if (outstanding > 0) out.add((po: po, outstanding: outstanding));
    }
    return out;
  }

  /// Record a payment to a supplier against AP and post Dr AP / Cr Cash.
  /// When [poId] is given the payment is allocated to that purchase order.
  Future<String> paySupplier({
    required String supplierId,
    required int amountMinor,
    String method = 'cash',
    String? reference,
    String? poId,
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
          poId: poId,
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
                po.status.isIn(['ordered', 'draft', 'partial']),
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

  /// Input-PPN rate (basis points) to split out of a goods receipt: only for a
  /// VAT-registered (PKP) company with a default tax rate; 0 = no input tax.
  /// (The rate's inclusive flag is a *sales-pricing* concept and is ignored
  /// here — a purchase cost is always the gross amount payable to the supplier,
  /// so the tax is split out of it inclusively, keeping ledger AP == apBalance.)
  Future<int> _purchaseTax() async {
    final settings =
        await (db.select(db.companySettings)
              ..where((t) => t.id.equals('default'))
              ..limit(1))
            .getSingleOrNull();
    if (settings?.isPkp != true) return 0;
    final rate = await accounting.defaultTaxRate();
    return rate?.basisPoints ?? 0;
  }

  /// Receive specific quantities. [quantities] maps a PO-line id to the qty to
  /// receive now (clamped to the line's outstanding). Appends +stock, bumps each
  /// line's `qtyReceived`, sets the PO to `received` (all lines complete) or
  /// `partial`, and posts the goods-receipt journal for the received value
  /// (input-PPN split for a PKP company). One transaction.
  Future<void> receiveLines(String poId, Map<String, int> quantities) async {
    final taxBp = await _purchaseTax();
    await db.transaction(() async {
      final po = await getPurchaseOrder(poId);
      if (po == null || po.status == 'received') return;
      final lines = await linesForPo(poId);
      final now = clock.nowMillis();
      var receivedValue = 0;
      var anyReceived = false;

      for (final l in lines) {
        final remaining = l.qtyOrdered - l.qtyReceived;
        final want = quantities[l.id] ?? 0;
        final take = want < 0 ? 0 : (want > remaining ? remaining : want);
        if (take <= 0) continue;
        anyReceived = true;
        await inventory.addMovement(
          variantId: l.variantId,
          locationId: po.locationId,
          qty: take,
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
            qtyReceived: l.qtyReceived + take,
            updatedAt: n,
            updatedHlc: hlc.pack(),
          ),
        );
        receivedValue += take * l.unitCostMinor;
      }
      if (!anyReceived) return;

      final fresh = await linesForPo(poId);
      final fullyReceived = fresh.every((l) => l.qtyReceived >= l.qtyOrdered);
      await writeSyncable<PurchaseOrder>(
        entityTable: 'purchase_orders',
        table: db.purchaseOrders,
        rowId: poId,
        build: (hlc, n) => po.copyWith(
          status: fullyReceived ? 'received' : 'partial',
          receivedAt: fullyReceived ? Value(now) : Value(po.receivedAt),
          updatedAt: n,
          updatedHlc: hlc.pack(),
        ),
      );

      final split = TaxMath.split(
        amountMinor: receivedValue,
        basisPoints: taxBp,
        inclusive: true, // PO cost is the gross owed; split tax out of it
      );
      await accounting.postPurchaseJournal(
        poId: poId,
        date: now,
        totalMinor: split.totalMinor,
        ppnMinor: split.taxMinor,
      );
    });
  }

  /// Receive all outstanding quantity on a PO (idempotent if already received).
  Future<void> receivePurchaseOrder(String poId) async {
    final po = await getPurchaseOrder(poId);
    if (po == null || po.status == 'received') return;
    final lines = await linesForPo(poId);
    await receiveLines(poId, {
      for (final l in lines) l.id: l.qtyOrdered - l.qtyReceived,
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
