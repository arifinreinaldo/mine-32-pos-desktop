import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/app_database.dart';
import '../../../core/di/providers.dart';
import '../data/inventory_repository.dart';
import '../domain/stock_models.dart';

final inventoryRepositoryProvider = Provider<InventoryRepository>((ref) {
  final services = ref.watch(appServicesProvider);
  return InventoryRepository(
    db: services.db,
    changeLog: services.changeLog,
    hlcService: services.hlc,
    clock: services.clock,
  );
});

class InventoryQuery extends Notifier<String> {
  @override
  String build() => '';
  void update(String value) => state = value;
}

final inventoryQueryProvider = NotifierProvider<InventoryQuery, String>(
  InventoryQuery.new,
);

final stockLevelsProvider = StreamProvider.autoDispose<List<StockLevel>>((ref) {
  final repo = ref.watch(inventoryRepositoryProvider);
  final query = ref.watch(inventoryQueryProvider);
  return repo.watchStockLevels(query: query);
});

final locationsProvider = StreamProvider.autoDispose<List<Location>>((ref) {
  return ref.watch(inventoryRepositoryProvider).watchLocations();
});
