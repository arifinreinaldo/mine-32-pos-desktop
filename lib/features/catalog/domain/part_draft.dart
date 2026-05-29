import '../../../core/money/money.dart';

/// Editable representation of a "simple part" (a product plus its default
/// variant) used by the editor. `variantId`/`productId` are null when creating.
class PartDraft {
  final String? variantId;
  final String? productId;
  final String name;
  final String sku;
  final String? barcode;
  final String? brandName;
  final String? description;
  final Money price;
  final Money cost;
  final Money coreCharge;
  final String unit;
  final bool isActive;

  const PartDraft({
    this.variantId,
    this.productId,
    required this.name,
    required this.sku,
    this.barcode,
    this.brandName,
    this.description,
    required this.price,
    required this.cost,
    required this.coreCharge,
    this.unit = 'each',
    this.isActive = true,
  });

  bool get isNew => variantId == null;

  static PartDraft empty() => const PartDraft(
    name: '',
    sku: '',
    price: Money(0),
    cost: Money(0),
    coreCharge: Money(0),
  );

  PartDraft copyWith({
    String? name,
    String? sku,
    String? barcode,
    String? brandName,
    String? description,
    Money? price,
    Money? cost,
    Money? coreCharge,
    String? unit,
    bool? isActive,
  }) {
    return PartDraft(
      variantId: variantId,
      productId: productId,
      name: name ?? this.name,
      sku: sku ?? this.sku,
      barcode: barcode ?? this.barcode,
      brandName: brandName ?? this.brandName,
      description: description ?? this.description,
      price: price ?? this.price,
      cost: cost ?? this.cost,
      coreCharge: coreCharge ?? this.coreCharge,
      unit: unit ?? this.unit,
      isActive: isActive ?? this.isActive,
    );
  }
}
