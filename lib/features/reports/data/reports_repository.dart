import 'package:drift/drift.dart';

import '../../../core/database/app_database.dart';
import '../../../core/money/money.dart';

class SalesSummary {
  final int count;
  final Money total;
  final Money dpp; // tax base
  final Money ppn; // output tax
  const SalesSummary({
    required this.count,
    required this.total,
    required this.dpp,
    required this.ppn,
  });
}

class DayTotal {
  final DateTime day;
  final Money total;
  const DayTotal(this.day, this.total);
}

class PartSales {
  final String description;
  final int qty;
  final Money total;
  const PartSales(this.description, this.qty, this.total);
}

/// Composite payload for the reports screen.
class ReportData {
  final SalesSummary summary;
  final List<DayTotal> byDay;
  final List<PartSales> topParts;
  const ReportData({
    required this.summary,
    required this.byDay,
    required this.topParts,
  });
}

/// Read-only reporting queries (no writes / no sync).
class ReportsRepository {
  final AppDatabase db;
  ReportsRepository(this.db);

  Future<ReportData> loadReport({
    required int fromMs,
    required int toMs,
  }) async {
    final sales =
        await (db.select(db.sales)..where(
              (t) =>
                  t.deletedAt.isNull() &
                  t.status.equals('completed') &
                  t.createdAt.isBiggerOrEqualValue(fromMs) &
                  t.createdAt.isSmallerThanValue(toMs),
            ))
            .get();

    var total = 0;
    var dpp = 0;
    var ppn = 0;
    final byDayMap = <int, int>{}; // epoch-day -> total
    for (final s in sales) {
      total += s.totalMinor;
      dpp += s.subtotalMinor;
      ppn += s.taxTotalMinor;
      final dayKey = s.createdAt ~/ 86400000;
      byDayMap[dayKey] = (byDayMap[dayKey] ?? 0) + s.totalMinor;
    }

    final byDay =
        (byDayMap.entries.toList()..sort((a, b) => a.key.compareTo(b.key)))
            .map(
              (e) => DayTotal(
                DateTime.fromMillisecondsSinceEpoch(
                  e.key * 86400000,
                  isUtc: true,
                ),
                Money(e.value),
              ),
            )
            .toList();

    final lines =
        await (db.select(db.saleLines)..where(
              (t) =>
                  t.deletedAt.isNull() &
                  t.createdAt.isBiggerOrEqualValue(fromMs) &
                  t.createdAt.isSmallerThanValue(toMs),
            ))
            .get();
    final partQty = <String, int>{};
    final partTotal = <String, int>{};
    for (final l in lines) {
      partQty[l.description] = (partQty[l.description] ?? 0) + l.qty;
      partTotal[l.description] =
          (partTotal[l.description] ?? 0) + l.lineTotalMinor;
    }
    final topParts =
        (partTotal.entries.toList()..sort((a, b) => b.value.compareTo(a.value)))
            .take(5)
            .map((e) => PartSales(e.key, partQty[e.key] ?? 0, Money(e.value)))
            .toList();

    return ReportData(
      summary: SalesSummary(
        count: sales.length,
        total: Money(total),
        dpp: Money(dpp),
        ppn: Money(ppn),
      ),
      byDay: byDay,
      topParts: topParts,
    );
  }
}
