import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/di/providers.dart';
import '../../accounting/presentation/accounting_controller.dart';
import '../../catalog/domain/catalog_item.dart';
import '../../catalog/presentation/catalog_controller.dart';
import '../../inventory/presentation/inventory_controller.dart';
import '../data/sales_repository.dart';
import '../domain/cart.dart';

final salesRepositoryProvider = Provider<SalesRepository>((ref) {
  final services = ref.watch(appServicesProvider);
  return SalesRepository(
    db: services.db,
    changeLog: services.changeLog,
    hlcService: services.hlc,
    clock: services.clock,
    inventory: ref.watch(inventoryRepositoryProvider),
    accounting: ref.watch(accountingRepositoryProvider),
  );
});

/// The in-progress cart for the Sell screen.
class CartController extends Notifier<Cart> {
  @override
  Cart build() => const Cart();

  void addItem(CatalogItem item) {
    final index = state.lines.indexWhere((l) => l.variantId == item.variantId);
    if (index >= 0) {
      final lines = [...state.lines];
      lines[index] = lines[index].copyWith(qty: lines[index].qty + 1);
      state = Cart(lines: lines);
    } else {
      state = Cart(
        lines: [
          ...state.lines,
          CartLine(
            variantId: item.variantId,
            sku: item.sku,
            name: item.productName,
            unitPrice: item.price,
            unitCost: item.cost,
          ),
        ],
      );
    }
  }

  void setQty(String variantId, int qty) {
    if (qty <= 0) {
      removeLine(variantId);
      return;
    }
    state = Cart(
      lines: state.lines
          .map((l) => l.variantId == variantId ? l.copyWith(qty: qty) : l)
          .toList(),
    );
  }

  void removeLine(String variantId) {
    state = Cart(
      lines: state.lines.where((l) => l.variantId != variantId).toList(),
    );
  }

  void clear() => state = const Cart();
}

final cartProvider = NotifierProvider<CartController, Cart>(CartController.new);

/// Search text for the Sell screen's part lookup.
class SellSearch extends Notifier<String> {
  @override
  String build() => '';
  void update(String value) => state = value;
}

final sellSearchProvider = NotifierProvider<SellSearch, String>(SellSearch.new);

/// Results for the Sell search (empty until something is typed).
final sellResultsProvider = StreamProvider.autoDispose<List<CatalogItem>>((
  ref,
) {
  final query = ref.watch(sellSearchProvider);
  if (query.trim().isEmpty) {
    return Stream.value(const <CatalogItem>[]);
  }
  return ref.watch(catalogRepositoryProvider).watch(query: query);
});
