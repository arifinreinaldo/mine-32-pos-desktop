import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../../../core/database/app_database.dart';
import '../../../core/database/sync_repository.dart';
import '../../../core/sync/change_record.dart';
import '../domain/customer_draft.dart';

/// Customers + their vehicles, plus AR (outstanding balance) and purchase
/// history. All mutations replicate as master data (LWW).
class CustomersRepository extends SyncRepository {
  final Uuid _uuid;

  CustomersRepository({
    required super.db,
    required super.changeLog,
    required super.hlcService,
    required super.clock,
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

  /// Outstanding balance (sum of total - paid over the customer's sales).
  Future<int> arBalance(String customerId) async {
    final s = db.sales;
    final outstanding = (s.totalMinor - s.paidTotalMinor).sum();
    final row =
        await (db.selectOnly(s)
              ..addColumns([outstanding])
              ..where(
                s.customerId.equals(customerId) &
                    s.deletedAt.isNull() &
                    s.status.equals('completed'),
              ))
            .getSingleOrNull();
    return row?.read(outstanding) ?? 0;
  }

  Stream<int> watchArBalance(String customerId) {
    final s = db.sales;
    final outstanding = (s.totalMinor - s.paidTotalMinor).sum();
    return (db.selectOnly(s)
          ..addColumns([outstanding])
          ..where(
            s.customerId.equals(customerId) &
                s.deletedAt.isNull() &
                s.status.equals('completed'),
          ))
        .watchSingleOrNull()
        .map((row) => row?.read(outstanding) ?? 0);
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
