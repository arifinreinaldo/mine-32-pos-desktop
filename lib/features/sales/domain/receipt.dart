/// A single printed line on a receipt (money pre-formatted to strings so the
/// PDF builder stays independent of currency logic).
class ReceiptLine {
  final String name;
  final int qty;
  final String unitPrice;
  final String lineTotal;
  const ReceiptLine({
    required this.name,
    required this.qty,
    required this.unitPrice,
    required this.lineTotal,
  });
}

/// Everything needed to render a sale receipt / simple faktur.
class ReceiptData {
  final String companyName;
  final String? address;
  final String? npwp;
  final String number;
  final int dateMs;
  final List<ReceiptLine> lines;
  final String? dpp; // shown when PPN applies
  final String? ppn;
  final String total;
  final String paid;
  final String change;
  final String? footer;

  const ReceiptData({
    required this.companyName,
    required this.number,
    required this.dateMs,
    required this.lines,
    required this.total,
    required this.paid,
    required this.change,
    this.address,
    this.npwp,
    this.dpp,
    this.ppn,
    this.footer,
  });
}
