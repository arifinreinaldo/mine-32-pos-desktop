/// Editable company configuration (single 'default' row).
class SettingsDraft {
  final String name;
  final String? legalName;
  final String? npwp; // company tax id (NPWP in Indonesia)
  final bool isPkp; // VAT-registered (charges PPN)
  final bool taxInclusive;
  final String? address;
  final String? phone;
  final String? email;
  final String currency;
  final int currencyScale;
  final String? receiptHeader;
  final String? receiptFooter;

  const SettingsDraft({
    required this.name,
    this.legalName,
    this.npwp,
    this.isPkp = false,
    this.taxInclusive = true,
    this.address,
    this.phone,
    this.email,
    this.currency = 'USD',
    this.currencyScale = 2,
    this.receiptHeader,
    this.receiptFooter,
  });
}
