/// Editable customer. `id` is null when creating.
class CustomerDraft {
  final String? id;
  final String name;
  final String? phone;
  final String? email;
  final String? npwp;
  final String? address;
  final int creditLimitMinor;
  final String? notes;

  const CustomerDraft({
    this.id,
    required this.name,
    this.phone,
    this.email,
    this.npwp,
    this.address,
    this.creditLimitMinor = 0,
    this.notes,
  });
}
