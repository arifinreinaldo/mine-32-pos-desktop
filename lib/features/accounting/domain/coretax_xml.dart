import '../../../core/money/money.dart';

/// One sale line inside a faktur for the CoreTax XML export.
class FakturXmlLine {
  final String name;
  final int qty;
  final int unitPriceMinor;
  final int dppMinor; // line tax base
  final int ppnMinor; // line VAT
  const FakturXmlLine({
    required this.name,
    required this.qty,
    required this.unitPriceMinor,
    required this.dppMinor,
    required this.ppnMinor,
  });
}

/// One tax invoice (faktur) with its goods lines.
class FakturXmlInvoice {
  final int dateMs;
  final String refNumber; // our sale number, exported as RefDesc
  final String? buyerName;
  final String? buyerNpwp;
  final List<FakturXmlLine> lines;
  const FakturXmlInvoice({
    required this.dateMs,
    required this.refNumber,
    required this.lines,
    this.buyerName,
    this.buyerNpwp,
  });
}

/// 16-zero TIN: CoreTax's convention for end-consumer buyers without an NPWP.
const String coreTaxEndConsumerTin = '0000000000000000';

/// Builds a CoreTax-style `TaxInvoiceBulk` XML document for the period's
/// output-tax invoices, following the published bulk-import structure
/// (TIN, ListOfTaxInvoice → TaxInvoice → ListOfGoodService → GoodService).
/// Field notes:
/// - [trxCode] defaults to '04' (retail/“DPP nilai lain” practice); adjust to
///   your KPP guidance before filing.
/// - Buyers without an NPWP get the 16-zero end-consumer TIN.
/// - Amounts are plain decimals at [scale] (IDR → whole numbers).
/// This is a best-effort export of the documented structure — always validate
/// against the current DJP schema before submitting.
String buildCoreTaxXml({
  required String sellerTin,
  required List<FakturXmlInvoice> invoices,
  int scale = 0,
  String trxCode = '04',
}) {
  final b = StringBuffer()
    ..writeln('<?xml version="1.0" encoding="utf-8"?>')
    ..writeln('<TaxInvoiceBulk>')
    ..writeln('  <TIN>${_esc(sellerTin)}</TIN>')
    ..writeln('  <ListOfTaxInvoice>');

  for (final inv in invoices) {
    final date = DateTime.fromMillisecondsSinceEpoch(inv.dateMs, isUtc: true);
    final dateStr =
        '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
    final buyerTin = (inv.buyerNpwp == null || inv.buyerNpwp!.trim().isEmpty)
        ? coreTaxEndConsumerTin
        : inv.buyerNpwp!.trim();
    b
      ..writeln('    <TaxInvoice>')
      ..writeln('      <TaxInvoiceDate>$dateStr</TaxInvoiceDate>')
      ..writeln('      <TaxInvoiceOpt>Normal</TaxInvoiceOpt>')
      ..writeln('      <TrxCode>${_esc(trxCode)}</TrxCode>')
      ..writeln('      <RefDesc>${_esc(inv.refNumber)}</RefDesc>')
      ..writeln('      <SellerIDTKU>${_esc(sellerTin)}000000</SellerIDTKU>')
      ..writeln('      <BuyerTin>${_esc(buyerTin)}</BuyerTin>')
      ..writeln('      <BuyerDocument>TIN</BuyerDocument>')
      ..writeln('      <BuyerCountry>IDN</BuyerCountry>')
      ..writeln('      <BuyerName>${_esc(inv.buyerName ?? 'Umum')}</BuyerName>')
      ..writeln('      <BuyerIDTKU>${_esc(buyerTin)}000000</BuyerIDTKU>')
      ..writeln('      <ListOfGoodService>');
    for (final l in inv.lines) {
      final vatRate = l.dppMinor == 0
          ? 0
          : ((l.ppnMinor * 100 + l.dppMinor ~/ 2) ~/ l.dppMinor);
      b
        ..writeln('        <GoodService>')
        ..writeln('          <Opt>A</Opt>')
        ..writeln('          <Code>000000</Code>')
        ..writeln('          <Name>${_esc(l.name)}</Name>')
        ..writeln('          <Unit>UM.0021</Unit>')
        ..writeln('          <Price>${_money(l.unitPriceMinor, scale)}</Price>')
        ..writeln('          <Qty>${l.qty}</Qty>')
        ..writeln('          <TotalDiscount>0</TotalDiscount>')
        ..writeln('          <TaxBase>${_money(l.dppMinor, scale)}</TaxBase>')
        ..writeln(
          '          <OtherTaxBase>${_money(l.dppMinor, scale)}</OtherTaxBase>',
        )
        ..writeln('          <VATRate>$vatRate</VATRate>')
        ..writeln('          <VAT>${_money(l.ppnMinor, scale)}</VAT>')
        ..writeln('          <STLGRate>0</STLGRate>')
        ..writeln('          <STLG>0</STLG>')
        ..writeln('        </GoodService>');
    }
    b
      ..writeln('      </ListOfGoodService>')
      ..writeln('    </TaxInvoice>');
  }

  b
    ..writeln('  </ListOfTaxInvoice>')
    ..writeln('</TaxInvoiceBulk>');
  return b.toString();
}

String _money(int minor, int scale) => Money(minor).toMajorString(scale: scale);

String _esc(String v) => v
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;')
    .replaceAll("'", '&apos;');
