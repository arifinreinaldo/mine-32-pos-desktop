import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mine32_pos/core/money/money.dart';
import 'package:mine32_pos/features/catalog/domain/catalog_item.dart';
import 'package:mine32_pos/features/sales/domain/cart.dart';
import 'package:mine32_pos/features/sales/presentation/sell_controller.dart';

CatalogItem _item(
  String id, {
  int price = 1000,
  int cost = 600,
  int wholesale = 0,
}) => CatalogItem(
  variantId: id,
  productId: 'p-$id',
  sku: id,
  barcode: null,
  productName: 'Part $id',
  variantName: 'Default',
  brandName: null,
  price: Money(price),
  wholesalePrice: Money(wholesale),
  cost: Money(cost),
  isActive: true,
);

void main() {
  group('Cart math', () {
    test('line and cart totals account for discount', () {
      const line = CartLine(
        variantId: 'v1',
        sku: 'v1',
        name: 'Part',
        unitPrice: Money(1000),
        unitCost: Money(600),
        qty: 3,
        discount: Money(200),
      );
      expect(line.gross, const Money(3000));
      expect(line.total, const Money(2800));

      final cart = Cart(lines: [line]);
      expect(cart.subtotal, const Money(3000));
      expect(cart.discountTotal, const Money(200));
      expect(cart.total, const Money(2800));
      expect(cart.itemCount, 3);
    });
  });

  group('CartController', () {
    test('adding the same item twice increments quantity', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final ctrl = container.read(cartProvider.notifier);

      ctrl.addItem(_item('A'));
      ctrl.addItem(_item('A'));
      ctrl.addItem(_item('B'));

      final cart = container.read(cartProvider);
      expect(cart.lines.length, 2);
      expect(cart.itemCount, 3);
      expect(cart.lines.firstWhere((l) => l.sku == 'A').qty, 2);
    });

    test('setQty to zero removes the line; clear empties the cart', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final ctrl = container.read(cartProvider.notifier);

      ctrl.addItem(_item('A'));
      ctrl.addItem(_item('B'));
      ctrl.setQty('A', 0);
      expect(container.read(cartProvider).lines.length, 1);

      ctrl.clear();
      expect(container.read(cartProvider).isEmpty, isTrue);
    });

    test('park stores the cart and recall returns it once', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final cartCtrl = container.read(cartProvider.notifier);
      final parkedCtrl = container.read(parkedSalesProvider.notifier);

      cartCtrl.addItem(_item('A'));
      cartCtrl.addItem(_item('B'));
      final parkedCart = container.read(cartProvider);

      parkedCtrl.park(
        parkedCart,
        customerId: 'cust-1',
        at: DateTime(2026, 6, 12, 9, 30),
      );
      cartCtrl.clear();
      expect(container.read(parkedSalesProvider), hasLength(1));
      expect(
        container.read(parkedSalesProvider).single.label,
        '2 item(s) · 09:30',
      );

      // Recall restores the exact cart + customer and consumes the slot.
      final recalled = parkedCtrl.recallAt(0)!;
      expect(recalled.customerId, 'cust-1');
      cartCtrl.replace(recalled.cart);
      expect(container.read(cartProvider).itemCount, 2);
      expect(container.read(parkedSalesProvider), isEmpty);

      // Out-of-range recall is null; parking an empty cart is a no-op.
      expect(parkedCtrl.recallAt(0), isNull);
      parkedCtrl.park(const Cart());
      expect(container.read(parkedSalesProvider), isEmpty);
    });

    test('wholesale tier re-prices lines (with retail fallback)', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final ctrl = container.read(cartProvider.notifier);

      ctrl.addItem(_item('A', price: 1000, wholesale: 800)); // has wholesale
      ctrl.addItem(_item('B', price: 500)); // no wholesale → retail fallback

      // Retail by default.
      expect(container.read(cartProvider).total, const Money(1500));

      // Switch to wholesale: A → 800, B stays 500.
      ctrl.setWholesale(true);
      final cart = container.read(cartProvider);
      expect(cart.wholesale, isTrue);
      expect(cart.total, const Money(1300));

      // The flag survives further edits (e.g. qty change).
      ctrl.setQty('A', 2); // 2×800 + 500
      expect(container.read(cartProvider).total, const Money(2100));

      // Back to retail.
      ctrl.setWholesale(false);
      expect(
        container.read(cartProvider).total,
        const Money(2500),
      ); // 2×1000+500
    });

    test('a discount on a wholesale line clamps to the wholesale gross', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final ctrl = container.read(cartProvider.notifier);

      ctrl.addItem(_item('A', price: 1000, wholesale: 600));
      ctrl.setWholesale(true); // line bills at 600

      // A discount above the wholesale gross (600) but below retail (1000) must
      // clamp to 600 so the total never goes negative.
      ctrl.setLineDiscount('A', const Money(800));
      expect(
        container.read(cartProvider).lines.single.discount,
        const Money(600),
      );
      expect(container.read(cartProvider).total, const Money(0));
    });

    test('setLineDiscount applies and clamps to the line gross', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final ctrl = container.read(cartProvider.notifier);

      ctrl.addItem(_item('A', price: 1000)); // qty 1 → gross 1000
      ctrl.setQty('A', 2); // gross 2000

      ctrl.setLineDiscount('A', const Money(300));
      expect(container.read(cartProvider).total, const Money(1700));

      // Over-discount clamps to the gross (never negative total).
      ctrl.setLineDiscount('A', const Money(99999));
      expect(container.read(cartProvider).total, const Money(0));
      expect(
        container.read(cartProvider).lines.single.discount,
        const Money(2000),
      );

      // Negative clamps to zero.
      ctrl.setLineDiscount('A', const Money(-50));
      expect(
        container.read(cartProvider).lines.single.discount,
        const Money(0),
      );
    });
  });
}
