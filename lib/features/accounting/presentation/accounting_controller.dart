import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/app_database.dart';
import '../../../core/di/providers.dart';
import '../data/accounting_repository.dart';
import '../domain/accounting_models.dart';

final accountingRepositoryProvider = Provider<AccountingRepository>((ref) {
  final services = ref.watch(appServicesProvider);
  return AccountingRepository(
    db: services.db,
    changeLog: services.changeLog,
    hlcService: services.hlc,
    clock: services.clock,
  );
});

/// The default tax rate (e.g. PPN 11%) applied at checkout, if any.
final defaultTaxRateProvider = FutureProvider<TaxRate?>((ref) {
  return ref.watch(accountingRepositoryProvider).defaultTaxRate();
});

final trialBalanceProvider = StreamProvider.autoDispose<List<TrialBalanceRow>>((
  ref,
) {
  return ref.watch(accountingRepositoryProvider).watchTrialBalance();
});
