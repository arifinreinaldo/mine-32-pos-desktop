import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/di/providers.dart';
import '../data/reports_repository.dart';

class DateRange {
  final int fromMs;
  final int toMs;
  final String label;
  const DateRange({
    required this.fromMs,
    required this.toMs,
    required this.label,
  });
}

DateRange rangeToday() {
  final now = DateTime.now();
  final start = DateTime(now.year, now.month, now.day);
  return DateRange(
    fromMs: start.millisecondsSinceEpoch,
    toMs: start.add(const Duration(days: 1)).millisecondsSinceEpoch,
    label: 'Today',
  );
}

DateRange rangeLast7() {
  final now = DateTime.now();
  final end = DateTime(
    now.year,
    now.month,
    now.day,
  ).add(const Duration(days: 1));
  final start = end.subtract(const Duration(days: 7));
  return DateRange(
    fromMs: start.millisecondsSinceEpoch,
    toMs: end.millisecondsSinceEpoch,
    label: 'Last 7 days',
  );
}

DateRange rangeThisMonth() {
  final now = DateTime.now();
  final start = DateTime(now.year, now.month);
  final end = DateTime(now.year, now.month + 1);
  return DateRange(
    fromMs: start.millisecondsSinceEpoch,
    toMs: end.millisecondsSinceEpoch,
    label: 'This month',
  );
}

class ReportRange extends Notifier<DateRange> {
  @override
  DateRange build() => rangeThisMonth();
  void today() => state = rangeToday();
  void last7() => state = rangeLast7();
  void thisMonth() => state = rangeThisMonth();
}

final reportRangeProvider = NotifierProvider<ReportRange, DateRange>(
  ReportRange.new,
);

final reportsRepositoryProvider = Provider<ReportsRepository>(
  (ref) => ReportsRepository(ref.watch(databaseProvider)),
);

final reportDataProvider = FutureProvider.autoDispose<ReportData>((ref) {
  final range = ref.watch(reportRangeProvider);
  return ref
      .watch(reportsRepositoryProvider)
      .loadReport(fromMs: range.fromMs, toMs: range.toMs);
});
