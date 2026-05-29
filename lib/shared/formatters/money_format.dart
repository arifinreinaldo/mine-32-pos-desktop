import '../../core/money/money.dart';

/// Formats [Money] for display with a currency symbol and thousands grouping.
/// Exact (works from integer minor units; no floating point). Currency symbol
/// will later come from company settings; defaults to '$'.
class MoneyFormat {
  final String symbol;
  final int scale;
  const MoneyFormat({this.symbol = r'$', this.scale = 2});

  static const Map<String, String> _symbols = {
    'USD': r'$',
    'IDR': 'Rp ',
    'EUR': '€',
    'GBP': '£',
    'SGD': r'S$',
    'MYR': 'RM ',
    'AUD': r'A$',
  };

  /// Build a formatter for a currency code + minor-unit scale (e.g. IDR → "Rp ",
  /// scale 0). Falls back to the code itself when the symbol is unknown.
  factory MoneyFormat.forCurrency(String currencyCode, int scale) {
    return MoneyFormat(
      symbol: _symbols[currencyCode] ?? '$currencyCode ',
      scale: scale,
    );
  }

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
