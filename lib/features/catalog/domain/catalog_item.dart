import '../../../core/money/money.dart';

/// A flattened, display-ready catalog row (one per sellable variant), joining
/// the variant with its product and brand. Pure domain — no Drift types.
class CatalogItem {
  final String variantId;
  final String productId;
  final String sku;
  final String? barcode;
  final String productName;
  final String variantName;
  final String? brandName;
  final Money price;
  final Money cost;
  final bool isActive;

  const CatalogItem({
    required this.variantId,
    required this.productId,
    required this.sku,
    required this.barcode,
    required this.productName,
    required this.variantName,
    required this.brandName,
    required this.price,
    required this.cost,
    required this.isActive,
  });

  /// Margin as a fraction (e.g. 0.4 = 40%); null when price is zero.
  double? get marginPct {
    if (price.minorUnits == 0) return null;
    return (price.minorUnits - cost.minorUnits) / price.minorUnits;
  }
}
