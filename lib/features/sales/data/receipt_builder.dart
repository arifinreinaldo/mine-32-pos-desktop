import '../../../core/database/app_database.dart';
import '../../../core/money/money.dart';
import '../../../shared/formatters/money_format.dart';
import '../domain/receipt.dart';

/// Builds the [ReceiptData] for a completed sale from its persisted rows. Shared
/// by checkout (print on complete) and the sales history (reprint).
ReceiptData buildSaleReceiptData({
  required Sale sale,
  required List<SaleLine> lines,
  required MoneyFormat money,
  String companyName = 'My Auto Parts',
  String? address,
  String? npwp,
  String? footer,
}) {
  final hasTax = sale.taxTotalMinor > 0;
  final change = sale.paidTotalMinor - sale.totalMinor;
  return ReceiptData(
    companyName: companyName,
    address: address,
    npwp: npwp,
    number: sale.number,
    dateMs: sale.createdAt,
    lines: [
      for (final l in lines)
        ReceiptLine(
          name: l.description,
          qty: l.qty,
          unitPrice: money.format(Money(l.unitPriceMinor)),
          lineTotal: money.format(Money(l.lineTotalMinor)),
        ),
    ],
    dpp: hasTax ? money.format(Money(sale.subtotalMinor)) : null,
    ppn: hasTax ? money.format(Money(sale.taxTotalMinor)) : null,
    total: money.format(Money(sale.totalMinor)),
    paid: money.format(Money(sale.paidTotalMinor)),
    change: money.format(Money(change < 0 ? 0 : change)),
    footer: footer,
  );
}
