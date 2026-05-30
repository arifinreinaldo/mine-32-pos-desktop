import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/app_database.dart';
import '../../../core/di/providers.dart';
import '../../accounting/presentation/accounting_controller.dart';
import '../data/customers_repository.dart';

final customersRepositoryProvider = Provider<CustomersRepository>((ref) {
  final services = ref.watch(appServicesProvider);
  return CustomersRepository(
    db: services.db,
    changeLog: services.changeLog,
    hlcService: services.hlc,
    clock: services.clock,
    accounting: ref.watch(accountingRepositoryProvider),
  );
});

class CustomerQuery extends Notifier<String> {
  @override
  String build() => '';
  void update(String value) => state = value;
}

final customerQueryProvider = NotifierProvider<CustomerQuery, String>(
  CustomerQuery.new,
);

final customersProvider = StreamProvider.autoDispose<List<Customer>>((ref) {
  final repo = ref.watch(customersRepositoryProvider);
  return repo.watch(query: ref.watch(customerQueryProvider));
});

/// Currently selected customer in the Customers screen (master-detail).
class SelectedCustomer extends Notifier<String?> {
  @override
  String? build() => null;
  void select(String? id) => state = id;
}

final selectedCustomerProvider = NotifierProvider<SelectedCustomer, String?>(
  SelectedCustomer.new,
);

final customerVehiclesProvider = StreamProvider.autoDispose
    .family<List<CustomerVehicle>, String>(
      (ref, id) => ref.watch(customersRepositoryProvider).watchVehicles(id),
    );

final customerArProvider = FutureProvider.autoDispose.family<int, String>(
  (ref, id) => ref.watch(customersRepositoryProvider).arBalance(id),
);

final customerHistoryProvider = FutureProvider.autoDispose
    .family<List<Sale>, String>(
      (ref, id) => ref.watch(customersRepositoryProvider).purchaseHistory(id),
    );
