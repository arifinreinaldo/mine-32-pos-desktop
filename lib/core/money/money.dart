import 'package:decimal/decimal.dart';

/// A monetary amount stored as integer **minor units** (e.g. cents) to avoid
/// floating-point error. Arithmetic requires a matching [currency].
///
/// Formatting with a currency symbol/locale is handled separately (see
/// `shared/formatters`); this type keeps money *exact*, not pretty.
class Money implements Comparable<Money> {
  static const String defaultCurrency = 'USD';

  final int minorUnits;
  final String currency;

  const Money(this.minorUnits, {this.currency = defaultCurrency});

  factory Money.zero([String currency = defaultCurrency]) =>
      Money(0, currency: currency);

  /// Build from a major-unit value (e.g. `12.5` -> `1250` minor at [scale] 2)
  /// using exact decimal math (never doubles).
  factory Money.fromMajor(
    Object major, {
    String currency = defaultCurrency,
    int scale = 2,
  }) {
    final d = major is Decimal ? major : Decimal.parse(major.toString());
    final factor = Decimal.fromBigInt(BigInt.from(10).pow(scale));
    final scaled = (d * factor).round();
    return Money(scaled.toBigInt().toInt(), currency: currency);
  }

  static Money sum(Iterable<Money> items, {String currency = defaultCurrency}) {
    var total = Money(0, currency: currency);
    for (final m in items) {
      total += m;
    }
    return total;
  }

  bool get isZero => minorUnits == 0;
  bool get isNegative => minorUnits < 0;
  bool get isPositive => minorUnits > 0;

  Money operator +(Money other) {
    _assertSameCurrency(other);
    return Money(minorUnits + other.minorUnits, currency: currency);
  }

  Money operator -(Money other) {
    _assertSameCurrency(other);
    return Money(minorUnits - other.minorUnits, currency: currency);
  }

  Money operator -() => Money(-minorUnits, currency: currency);

  Money operator *(int factor) =>
      Money(minorUnits * factor, currency: currency);

  Money abs() => Money(minorUnits.abs(), currency: currency);

  /// Major-unit string with [scale] decimals and no currency symbol,
  /// e.g. `Money(1250).toMajorString() == '12.50'`.
  String toMajorString({int scale = 2}) {
    final negative = minorUnits < 0;
    final digits = minorUnits.abs().toString().padLeft(scale + 1, '0');
    final cut = digits.length - scale;
    final whole = digits.substring(0, cut);
    final frac = scale == 0 ? '' : '.${digits.substring(cut)}';
    return '${negative ? '-' : ''}$whole$frac';
  }

  void _assertSameCurrency(Money other) {
    if (other.currency != currency) {
      throw ArgumentError('Currency mismatch: $currency vs ${other.currency}');
    }
  }

  @override
  int compareTo(Money other) {
    _assertSameCurrency(other);
    return minorUnits.compareTo(other.minorUnits);
  }

  bool operator <(Money o) => compareTo(o) < 0;
  bool operator <=(Money o) => compareTo(o) <= 0;
  bool operator >(Money o) => compareTo(o) > 0;
  bool operator >=(Money o) => compareTo(o) >= 0;

  @override
  bool operator ==(Object other) =>
      other is Money &&
      other.minorUnits == minorUnits &&
      other.currency == currency;

  @override
  int get hashCode => Object.hash(minorUnits, currency);

  @override
  String toString() => '$currency ${toMajorString()}';
}
