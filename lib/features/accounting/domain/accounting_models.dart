import '../../../core/money/money.dart';

/// Standard chart-of-accounts codes used by posting rules.
abstract final class AccountCode {
  static const String cash = '1-1000';
  static const String bank = '1-1100';
  static const String receivable = '1-1200';
  static const String inventory = '1-1400';
  static const String accountsPayable = '2-2000';
  static const String ppnOutput = '2-2100'; // PPN Keluaran (VAT payable)
  static const String ownerEquity = '3-3000';
  static const String salesRevenue = '4-4000';
  static const String cogs = '5-5000';
  static const String inventoryAdjustment = '5-9000';
}

/// One leg to post into a journal.
class JournalLineInput {
  final String accountId;
  final int debitMinor;
  final int creditMinor;
  final String? description;
  const JournalLineInput({
    required this.accountId,
    this.debitMinor = 0,
    this.creditMinor = 0,
    this.description,
  });
}

/// A row of the trial balance / account listing.
class TrialBalanceRow {
  final String accountId;
  final String code;
  final String name;
  final String type;
  final Money debit;
  final Money credit;
  const TrialBalanceRow({
    required this.accountId,
    required this.code,
    required this.name,
    required this.type,
    required this.debit,
    required this.credit,
  });

  /// Net balance (debit - credit); positive = debit balance.
  Money get balance => debit - credit;
}

/// PPN (VAT) summary for a period — the shape needed for Indonesian CoreTax
/// reporting (output tax = PPN Keluaran on sales).
class TaxSummary {
  final int salesCount;
  final Money dpp; // tax base
  final Money ppn; // output tax
  final Money grandTotal;
  const TaxSummary({
    required this.salesCount,
    required this.dpp,
    required this.ppn,
    required this.grandTotal,
  });
}
