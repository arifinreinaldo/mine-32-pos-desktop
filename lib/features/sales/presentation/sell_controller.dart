import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/di/providers.dart';
import '../../../core/money/money.dart';
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
      state = Cart(lines: lines, wholesale: state.wholesale);
    } else {
      state = Cart(
        wholesale: state.wholesale,
        lines: [
          ...state.lines,
          CartLine(
            variantId: item.variantId,
            sku: item.sku,
            name: item.productName,
            unitPrice: item.price,
            wholesaleUnitPrice: item.wholesalePrice,
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
      wholesale: state.wholesale,
      lines: state.lines
          .map((l) => l.variantId == variantId ? l.copyWith(qty: qty) : l)
          .toList(),
    );
  }

  void removeLine(String variantId) {
    state = Cart(
      wholesale: state.wholesale,
      lines: state.lines.where((l) => l.variantId != variantId).toList(),
    );
  }

  /// Set an absolute per-line discount, clamped to `[0, gross]`.
  void setLineDiscount(String variantId, Money discount) {
    state = Cart(
      wholesale: state.wholesale,
      lines: state.lines.map((l) {
        if (l.variantId != variantId) return l;
        final clamped = discount.minorUnits < 0
            ? const Money(0)
            : (discount.minorUnits > l.gross.minorUnits ? l.gross : discount);
        return l.copyWith(discount: clamped);
      }).toList(),
    );
  }

  /// Switch the cart between retail and wholesale pricing (set when a wholesale
  /// customer is attached).
  void setWholesale(bool wholesale) {
    if (state.wholesale == wholesale) return;
    state = Cart(lines: state.lines, wholesale: wholesale);
  }

  void clear() => state = const Cart();

  /// Replace the whole cart (used by recall of a parked sale).
  void replace(Cart cart) => state = cart;
}

final cartProvider = NotifierProvider<CartController, Cart>(CartController.new);

/// A sale set aside mid-checkout (kept in memory on this device only — parked
/// drafts are mutable and deliberately not synced; they're lost on app exit).
class ParkedSale {
  final Cart cart;
  final String? customerId;
  final DateTime parkedAt;
  const ParkedSale({
    required this.cart,
    required this.parkedAt,
    this.customerId,
  });

  String get label {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${cart.itemCount} item(s) · ${two(parkedAt.hour)}:${two(parkedAt.minute)}';
  }
}

class ParkedSales extends Notifier<List<ParkedSale>> {
  @override
  List<ParkedSale> build() => const [];

  void park(Cart cart, {String? customerId, DateTime? at}) {
    if (cart.isEmpty) return;
    state = [
      ...state,
      ParkedSale(
        cart: cart,
        customerId: customerId,
        parkedAt: at ?? DateTime.now(),
      ),
    ];
  }

  /// Remove and return the parked sale at [index] (null if out of range).
  ParkedSale? recallAt(int index) {
    if (index < 0 || index >= state.length) return null;
    final sale = state[index];
    state = [...state]..removeAt(index);
    return sale;
  }
}

final parkedSalesProvider = NotifierProvider<ParkedSales, List<ParkedSale>>(
  ParkedSales.new,
);

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

/// Customer attached to the in-progress sale (null = walk-in).
class SellCustomer extends Notifier<String?> {
  @override
  String? build() => null;
  void select(String? id) => state = id;
}

final sellCustomerProvider = NotifierProvider<SellCustomer, String?>(
  SellCustomer.new,
);
