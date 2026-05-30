import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/di/providers.dart';
import '../../accounting/presentation/accounting_controller.dart';
import '../../inventory/presentation/inventory_controller.dart';
import '../data/returns_repository.dart';

final returnsRepositoryProvider = Provider<ReturnsRepository>((ref) {
  final services = ref.watch(appServicesProvider);
  return ReturnsRepository(
    db: services.db,
    changeLog: services.changeLog,
    hlcService: services.hlc,
    clock: services.clock,
    inventory: ref.watch(inventoryRepositoryProvider),
    accounting: ref.watch(accountingRepositoryProvider),
  );
});

/// The sale lines of [saleId] that still have returnable quantity.
final returnableLinesProvider = FutureProvider.autoDispose
    .family<List<ReturnableLine>, String>((ref, saleId) {
      return ref.watch(returnsRepositoryProvider).returnableLines(saleId);
    });
