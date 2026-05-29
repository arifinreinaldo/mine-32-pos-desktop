import '../../../core/money/money.dart';

/// One faktur (tax-invoice) line for a CoreTax-style PPN export.
class FakturRow {
  final String number;
  final int dateMs;
  final String? buyerName;
  final String? buyerNpwp;
  final String? fakturNumber;
  final int dppMinor;
  final int ppnMinor;
  final int totalMinor;
  const FakturRow({
    required this.number,
    required this.dateMs,
    required this.dppMinor,
    required this.ppnMinor,
    required this.totalMinor,
    this.buyerName,
    this.buyerNpwp,
    this.fakturNumber,
  });
}

/// Builds a CSV of output-tax (PPN Keluaran) faktur rows for a period — the
/// shape a bookkeeper feeds into Indonesian CoreTax / e-Faktur. Pure function.
String buildCoreTaxCsv(List<FakturRow> rows, {int scale = 2}) {
  final out = StringBuffer()
    ..writeln('number,date,buyer_name,buyer_npwp,faktur_number,dpp,ppn,total');
  for (final r in rows) {
    final date = DateTime.fromMillisecondsSinceEpoch(
      r.dateMs,
      isUtc: true,
    ).toIso8601String();
    out.writeln(
      [
        _esc(r.number),
        _esc(date),
        _esc(r.buyerName ?? ''),
        _esc(r.buyerNpwp ?? ''),
        _esc(r.fakturNumber ?? ''),
        Money(r.dppMinor).toMajorString(scale: scale),
        Money(r.ppnMinor).toMajorString(scale: scale),
        Money(r.totalMinor).toMajorString(scale: scale),
      ].join(','),
    );
  }
  return out.toString();
}

String _esc(String value) {
  if (value.contains(',') || value.contains('"') || value.contains('\n')) {
    return '"${value.replaceAll('"', '""')}"';
  }
  return value;
}
