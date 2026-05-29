import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mine32_pos/core/money/money.dart';
import 'package:mine32_pos/features/catalog/domain/catalog_item.dart';
import 'package:mine32_pos/features/sales/domain/cart.dart';
import 'package:mine32_pos/features/sales/presentation/sell_controller.dart';

CatalogItem _item(String id, {int price = 1000, int cost = 600}) => CatalogItem(
  variantId: id,
  productId: 'p-$id',
  sku: id,
  barcode: null,
  productName: 'Part $id',
  variantName: 'Default',
  brandName: null,
  price: Money(price),
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
  });
}
