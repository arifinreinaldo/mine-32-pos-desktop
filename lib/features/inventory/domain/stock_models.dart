/// On-hand stock for a variant (summed across locations unless noted). Pure
/// domain — `onHand` is derived from the append-only movement ledger.
class StockLevel {
  final String variantId;
  final String sku;
  final String productName;
  final int onHand;

  const StockLevel({
    required this.variantId,
    required this.sku,
    required this.productName,
    required this.onHand,
  });

  bool get isLow => onHand <= 0;
}

/// Editable stock location.
class LocationDraft {
  final String? id;
  final String name;
  final String type; // store | warehouse
  final bool isDefault;

  const LocationDraft({
    this.id,
    required this.name,
    this.type = 'store',
    this.isDefault = false,
  });
}
