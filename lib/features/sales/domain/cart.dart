import '../../../core/money/money.dart';

/// One line in the in-progress sale (lives in memory until the sale completes).
class CartLine {
  final String variantId;
  final String sku;
  final String name;
  final Money unitPrice; // retail
  final Money wholesaleUnitPrice; // 0 = none (falls back to retail)
  final Money unitCost;
  final int qty;
  final Money discount;

  const CartLine({
    required this.variantId,
    required this.sku,
    required this.name,
    required this.unitPrice,
    required this.unitCost,
    this.wholesaleUnitPrice = const Money(0),
    this.qty = 1,
    this.discount = const Money(0),
  });

  /// Price actually charged for the given tier.
  Money effectiveUnitPrice(bool wholesale) =>
      (wholesale && wholesaleUnitPrice.minorUnits > 0)
      ? wholesaleUnitPrice
      : unitPrice;

  Money get gross => unitPrice * qty; // retail gross
  Money get total => gross - discount;
  Money effectiveGross(bool wholesale) => effectiveUnitPrice(wholesale) * qty;
  Money effectiveTotal(bool wholesale) => effectiveGross(wholesale) - discount;

  CartLine copyWith({int? qty, Money? discount}) => CartLine(
    variantId: variantId,
    sku: sku,
    name: name,
    unitPrice: unitPrice,
    wholesaleUnitPrice: wholesaleUnitPrice,
    unitCost: unitCost,
    qty: qty ?? this.qty,
    discount: discount ?? this.discount,
  );
}

/// The in-progress sale. [wholesale] is set when a wholesale customer is
/// attached, switching lines to their wholesale price.
class Cart {
  final List<CartLine> lines;
  final bool wholesale;
  const Cart({this.lines = const [], this.wholesale = false});

  Money get subtotal =>
      Money.sum(lines.map((l) => l.effectiveGross(wholesale)));
  Money get discountTotal => Money.sum(lines.map((l) => l.discount));
  Money get total => subtotal - discountTotal;
  int get itemCount => lines.fold(0, (sum, l) => sum + l.qty);
  bool get isEmpty => lines.isEmpty;
  bool get isNotEmpty => lines.isNotEmpty;
}

/// Outcome of completing a sale, for the receipt/confirmation.
class SaleResult {
  final String saleId;
  final String number;
  final Money total;
  final Money change;
  const SaleResult({
    required this.saleId,
    required this.number,
    required this.total,
    required this.change,
  });
}
