import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/app_database.dart';
import '../../reports/data/reports_repository.dart';
import '../../reports/presentation/reports_controller.dart';
import '../../sales/presentation/sell_controller.dart';

final todayReportProvider = FutureProvider.autoDispose<ReportData>((ref) {
  final range = rangeToday();
  return ref
      .watch(reportsRepositoryProvider)
      .loadReport(fromMs: range.fromMs, toMs: range.toMs);
});

final recentSalesProvider = StreamProvider.autoDispose<List<Sale>>((ref) {
  return ref.watch(salesRepositoryProvider).watchRecentSales(limit: 8);
});
