import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/app_database.dart';
import '../../../core/di/providers.dart';
import '../../accounting/presentation/accounting_controller.dart';
import '../../inventory/presentation/inventory_controller.dart';
import '../data/purchasing_repository.dart';

final purchasingRepositoryProvider = Provider<PurchasingRepository>((ref) {
  final services = ref.watch(appServicesProvider);
  return PurchasingRepository(
    db: services.db,
    changeLog: services.changeLog,
    hlcService: services.hlc,
    clock: services.clock,
    inventory: ref.watch(inventoryRepositoryProvider),
    accounting: ref.watch(accountingRepositoryProvider),
  );
});

class SupplierQuery extends Notifier<String> {
  @override
  String build() => '';
  void update(String value) => state = value;
}

final supplierQueryProvider = NotifierProvider<SupplierQuery, String>(
  SupplierQuery.new,
);

final suppliersProvider = StreamProvider.autoDispose<List<Supplier>>((ref) {
  final repo = ref.watch(purchasingRepositoryProvider);
  return repo.watchSuppliers(query: ref.watch(supplierQueryProvider));
});

final purchaseOrdersProvider = StreamProvider.autoDispose<List<PurchaseOrder>>((
  ref,
) {
  return ref.watch(purchasingRepositoryProvider).watchPurchaseOrders();
});

/// Outstanding payable to a supplier (refreshable).
final supplierApProvider = FutureProvider.autoDispose.family<int, String>(
  (ref, id) => ref.watch(purchasingRepositoryProvider).apBalance(id),
);

/// Units on the way per variant (open POs), for the inventory "Incoming" column.
final incomingByVariantProvider = StreamProvider.autoDispose<Map<String, int>>((
  ref,
) {
  return ref.watch(purchasingRepositoryProvider).watchIncomingByVariant();
});
