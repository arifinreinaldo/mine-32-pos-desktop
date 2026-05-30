import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/app_database.dart';
import 'sell_controller.dart';

/// Completed/recent sales, newest first, for the sales history list.
final recentSalesProvider = StreamProvider.autoDispose<List<Sale>>((ref) {
  return ref.watch(salesRepositoryProvider).watchRecentSales();
});

/// The sale currently selected in the history master-detail.
class SelectedSaleId extends Notifier<String?> {
  @override
  String? build() => null;
  void select(String? id) => state = id;
}

final selectedSaleIdProvider = NotifierProvider<SelectedSaleId, String?>(
  SelectedSaleId.new,
);

/// A sale plus its lines, for the detail panel.
class SaleDetail {
  final Sale sale;
  final List<SaleLine> lines;
  const SaleDetail(this.sale, this.lines);
}

final saleDetailProvider = FutureProvider.autoDispose
    .family<SaleDetail?, String>((ref, saleId) async {
      final repo = ref.watch(salesRepositoryProvider);
      final sale = await repo.getSale(saleId);
      if (sale == null) return null;
      final lines = await repo.linesForSale(saleId);
      return SaleDetail(sale, lines);
    });
