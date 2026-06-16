import '../../../core/money/money.dart';

/// Standard chart-of-accounts codes used by posting rules.
abstract final class AccountCode {
  static const String cash = '1-1000';
  static const String bank = '1-1100';
  static const String receivable = '1-1200';
  static const String ppnInput = '1-1300'; // PPN Masukan (recoverable VAT)
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

/// A journal header for the journal browser (with its posted total).
class JournalSummary {
  final String id;
  final int dateMs;
  final String source;
  final String? memo;
  final String? refType;
  final Money total; // sum of debits (== sum of credits)
  const JournalSummary({
    required this.id,
    required this.dateMs,
    required this.source,
    required this.total,
    this.memo,
    this.refType,
  });
}

/// One posted journal line, joined to its account, for the browser detail view.
class JournalLineView {
  final String accountCode;
  final String accountName;
  final Money debit;
  final Money credit;
  final String? description;
  const JournalLineView({
    required this.accountCode,
    required this.accountName,
    required this.debit,
    required this.credit,
    this.description,
  });
}

/// One account line on a financial statement (amount shown as a positive value
/// of its natural sign).
class StatementLine {
  final String code;
  final String name;
  final Money amount;
  const StatementLine({
    required this.code,
    required this.name,
    required this.amount,
  });
}

/// Profit & Loss (income statement) for a period.
class ProfitAndLoss {
  final List<StatementLine> income;
  final List<StatementLine> expense;
  final Money totalIncome;
  final Money totalExpense;
  const ProfitAndLoss({
    required this.income,
    required this.expense,
    required this.totalIncome,
    required this.totalExpense,
  });

  Money get netProfit => totalIncome - totalExpense;
}

/// Balance sheet as of a point in time. `equity` already includes retained
/// earnings (net income to date).
class BalanceSheet {
  final List<StatementLine> assets;
  final List<StatementLine> liabilities;
  final List<StatementLine> equity;
  final Money totalAssets;
  final Money totalLiabilities;
  final Money totalEquity;
  final Money retainedEarnings;
  const BalanceSheet({
    required this.assets,
    required this.liabilities,
    required this.equity,
    required this.totalAssets,
    required this.totalLiabilities,
    required this.totalEquity,
    required this.retainedEarnings,
  });

  /// Assets should equal liabilities + equity.
  bool get balanced =>
      totalAssets.minorUnits ==
      totalLiabilities.minorUnits + totalEquity.minorUnits;
}
