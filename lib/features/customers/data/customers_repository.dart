import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../../../core/database/app_database.dart';
import '../../../core/database/sync_repository.dart';
import '../../../core/sync/change_record.dart';
import '../../accounting/data/accounting_repository.dart';
import '../domain/customer_draft.dart';

/// Customers + their vehicles, plus AR (outstanding balance), receipts and
/// purchase history. Master data (LWW) except receipts (append-only events).
class CustomersRepository extends SyncRepository {
  final Uuid _uuid;

  /// When provided, settling a receipt posts the Dr Cash / Cr AR journal.
  final AccountingRepository? accounting;

  CustomersRepository({
    required super.db,
    required super.changeLog,
    required super.hlcService,
    required super.clock,
    this.accounting,
    Uuid? uuid,
  }) : _uuid = uuid ?? const Uuid();

  Stream<List<Customer>> watch({String query = ''}) {
    final c = db.customers;
    final statement = db.select(c)..where((t) => t.deletedAt.isNull());
    final trimmed = query.trim();
    if (trimmed.isNotEmpty) {
      final like = '%$trimmed%';
      statement.where(
        (t) => t.name.like(like) | t.phone.like(like) | t.email.like(like),
      );
    }
    statement.orderBy([(t) => OrderingTerm.asc(t.name)]);
    return statement.watch();
  }

  Future<Customer?> getCustomer(String id) {
    return (db.select(db.customers)
          ..where((t) => t.id.equals(id))
          ..limit(1))
        .getSingleOrNull();
  }

  Future<String> saveCustomer(CustomerDraft draft) async {
    final id = draft.id ?? _uuid.v7();
    final createdAt = draft.id == null
        ? clock.nowMillis()
        : await existingCreatedAt(db.customers, id) ?? clock.nowMillis();
    await writeSyncable<Customer>(
      entityTable: 'customers',
      table: db.customers,
      rowId: id,
      build: (hlc, now) => Customer(
        id: id,
        createdAt: createdAt,
        updatedAt: now,
        updatedHlc: hlc.pack(),
        name: draft.name,
        phone: draft.phone,
        email: draft.email,
        taxNumber: draft.npwp,
        address: draft.address,
        creditLimitMinor: draft.creditLimitMinor,
        priceTier: draft.priceTier,
        notes: draft.notes,
      ),
    );
    return id;
  }

  Future<void> deleteCustomer(String id) async {
    final row = await getCustomer(id);
    if (row == null) return;
    await writeSyncable<Customer>(
      entityTable: 'customers',
      table: db.customers,
      rowId: id,
      op: ChangeOp.delete,
      build: (hlc, now) => row.copyWith(
        deletedAt: Value(now),
        updatedAt: now,
        updatedHlc: hlc.pack(),
      ),
    );
  }

  // --- Vehicles ---

  Stream<List<CustomerVehicle>> watchVehicles(String customerId) {
    return (db.select(db.customerVehicles)
          ..where((t) => t.customerId.equals(customerId) & t.deletedAt.isNull())
          ..orderBy([(t) => OrderingTerm.asc(t.plate)]))
        .watch();
  }

  Future<String> addVehicle({
    required String customerId,
    String? plate,
    String? vin,
    String? description,
    String? notes,
  }) async {
    final id = _uuid.v7();
    await writeSyncable<CustomerVehicle>(
      entityTable: 'customer_vehicles',
      table: db.customerVehicles,
      rowId: id,
      build: (hlc, now) => CustomerVehicle(
        id: id,
        createdAt: now,
        updatedAt: now,
        updatedHlc: hlc.pack(),
        customerId: customerId,
        plate: plate,
        vin: vin,
        description: description,
        notes: notes,
      ),
    );
    return id;
  }

  Future<void> removeVehicle(String id) async {
    final row =
        await (db.select(db.customerVehicles)
              ..where((t) => t.id.equals(id))
              ..limit(1))
            .getSingleOrNull();
    if (row == null) return;
    await writeSyncable<CustomerVehicle>(
      entityTable: 'customer_vehicles',
      table: db.customerVehicles,
      rowId: id,
      op: ChangeOp.delete,
      build: (hlc, now) => row.copyWith(
        deletedAt: Value(now),
        updatedAt: now,
        updatedHlc: hlc.pack(),
      ),
    );
  }

  // --- AR & history ---

  /// Outstanding AR: on-account sale balances (total - paid) minus receipts.
  Future<int> arBalance(String customerId) async {
    final s = db.sales;
    final saleOutstanding = (s.totalMinor - s.paidTotalMinor).sum();
    final saleRow =
        await (db.selectOnly(s)
              ..addColumns([saleOutstanding])
              ..where(
                s.customerId.equals(customerId) &
                    s.deletedAt.isNull() &
                    s.status.equals('completed'),
              ))
            .getSingleOrNull();
    final fromSales = saleRow?.read(saleOutstanding) ?? 0;

    final r = db.customerReceipts;
    final receiptSum = r.amountMinor.sum();
    final receiptRow =
        await (db.selectOnly(r)
              ..addColumns([receiptSum])
              ..where(r.customerId.equals(customerId) & r.deletedAt.isNull()))
            .getSingleOrNull();
    final received = receiptRow?.read(receiptSum) ?? 0;

    return fromSales - received;
  }

  /// Record a receipt from a customer against AR and post Dr Cash / Cr AR.
  Future<String> receivePayment({
    required String customerId,
    required int amountMinor,
    String method = 'cash',
    String? reference,
  }) async {
    final id = _uuid.v7();
    await db.transaction(() async {
      await writeSyncable<CustomerReceipt>(
        entityTable: 'customer_receipts',
        table: db.customerReceipts,
        rowId: id,
        build: (hlc, now) => CustomerReceipt(
          id: id,
          createdAt: now,
          updatedAt: now,
          updatedHlc: hlc.pack(),
          customerId: customerId,
          amountMinor: amountMinor,
          method: method,
          reference: reference,
        ),
      );
      await accounting?.postReceiptJournal(
        refId: id,
        date: clock.nowMillis(),
        amountMinor: amountMinor,
        method: method,
      );
    });
    return id;
  }

  Future<List<Sale>> purchaseHistory(String customerId, {int limit = 50}) {
    return (db.select(db.sales)
          ..where(
            (t) =>
                t.customerId.equals(customerId) &
                t.deletedAt.isNull() &
                t.status.equals('completed'),
          )
          ..orderBy([(t) => OrderingTerm.desc(t.createdAt)])
          ..limit(limit))
        .get();
  }
}
