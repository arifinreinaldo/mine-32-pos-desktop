/// Canonical reasons for a stock movement (stored as text on the ledger).
abstract final class MovementReason {
  static const String adjustment = 'adjustment';
  static const String sale = 'sale';
  static const String purchase = 'purchase';
  static const String count = 'count';
  static const String transferIn = 'transfer_in';
  static const String transferOut = 'transfer_out';
  static const String customerReturn = 'return';

  static const List<String> all = [
    adjustment,
    sale,
    purchase,
    count,
    transferIn,
    transferOut,
    customerReturn,
  ];
}
