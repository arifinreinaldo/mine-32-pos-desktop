/// Editable supplier. `id` is null when creating.
class SupplierDraft {
  final String? id;
  final String name;
  final String? phone;
  final String? email;
  final String? npwp;
  final String? address;
  final String? terms;
  final String? notes;

  const SupplierDraft({
    this.id,
    required this.name,
    this.phone,
    this.email,
    this.npwp,
    this.address,
    this.terms,
    this.notes,
  });
}

/// A line to put on a new purchase order.
class PoLineInput {
  final String variantId;
  final String description;
  final int qty;
  final int unitCostMinor;
  const PoLineInput({
    required this.variantId,
    required this.description,
    required this.qty,
    required this.unitCostMinor,
  });
}
