/// Result of splitting an amount into tax base (DPP) and tax (PPN).
class TaxAmounts {
  /// Tax base — the "Dasar Pengenaan Pajak" (DPP) in Indonesian terms.
  final int baseMinor;

  /// Tax amount — PPN.
  final int taxMinor;

  /// What the customer pays (base + tax).
  final int totalMinor;

  const TaxAmounts({
    required this.baseMinor,
    required this.taxMinor,
    required this.totalMinor,
  });
}

/// Pure, integer (no floating point) tax arithmetic. [basisPoints] is the rate
/// in hundredths of a percent (1100 = 11%, 1200 = 12%). Half-up rounding.
abstract final class TaxMath {
  static TaxAmounts split({
    required int amountMinor,
    required int basisPoints,
    required bool inclusive,
  }) {
    if (basisPoints <= 0) {
      return TaxAmounts(
        baseMinor: amountMinor,
        taxMinor: 0,
        totalMinor: amountMinor,
      );
    }
    if (inclusive) {
      // amount already includes tax: base = amount * 10000 / (10000 + bp)
      final denom = 10000 + basisPoints;
      final base = (amountMinor * 10000 + denom ~/ 2) ~/ denom;
      final tax = amountMinor - base;
      return TaxAmounts(
        baseMinor: base,
        taxMinor: tax,
        totalMinor: amountMinor,
      );
    }
    // tax added on top of amount.
    final tax = (amountMinor * basisPoints + 5000) ~/ 10000;
    return TaxAmounts(
      baseMinor: amountMinor,
      taxMinor: tax,
      totalMinor: amountMinor + tax,
    );
  }
}
