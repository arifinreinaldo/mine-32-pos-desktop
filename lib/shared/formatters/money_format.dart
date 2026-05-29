import '../../core/money/money.dart';

/// Formats [Money] for display with a currency symbol and thousands grouping.
/// Exact (works from integer minor units; no floating point). Currency symbol
/// will later come from company settings; defaults to '$'.
class MoneyFormat {
  final String symbol;
  final int scale;
  const MoneyFormat({this.symbol = r'$', this.scale = 2});

  String format(Money money) {
    final raw = money.toMajorString(scale: scale); // e.g. -1234.50
    final negative = raw.startsWith('-');
    final body = negative ? raw.substring(1) : raw;
    final dot = body.indexOf('.');
    final intPart = dot < 0 ? body : body.substring(0, dot);
    final fracPart = dot < 0 ? '' : body.substring(dot);
    return '${negative ? '-' : ''}$symbol${_group(intPart)}$fracPart';
  }

  static String _group(String digits) {
    final buffer = StringBuffer();
    for (var i = 0; i < digits.length; i++) {
      if (i > 0 && (digits.length - i) % 3 == 0) buffer.write(',');
      buffer.write(digits[i]);
    }
    return buffer.toString();
  }
}
