import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../shared/formatters/money_format.dart';
import '../backup/backup_service.dart';
import '../database/app_database.dart';
import '../errors/app_error_reporter.dart';
import '../time/clock.dart';
import 'app_services.dart';

/// Root provider, overridden in `main()`/tests with a concrete [AppServices].
final appServicesProvider = Provider<AppServices>(
  (ref) => throw UnimplementedError('appServicesProvider must be overridden'),
);

final databaseProvider = Provider<AppDatabase>(
  (ref) => ref.watch(appServicesProvider).db,
);

final clockProvider = Provider<Clock>(
  (ref) => ref.watch(appServicesProvider).clock,
);

final deviceIdProvider = Provider<String>(
  (ref) => ref.watch(appServicesProvider).deviceId,
);

/// Full-database backup & restore over the registered syncable entities.
final backupServiceProvider = Provider<BackupService>((ref) {
  final services = ref.watch(appServicesProvider);
  return BackupService(db: services.db, registry: services.registry);
});

/// App-wide error sink. Overridden in `main()` with the installed singleton so
/// uncaught errors reach the UI; defaults to a standalone reporter otherwise.
final errorReporterProvider = Provider<AppErrorReporter>((ref) {
  final reporter = AppErrorReporter();
  ref.onDispose(reporter.dispose);
  return reporter;
});

/// Stream of user-facing error messages, listened to by the app shell.
final errorMessagesProvider = StreamProvider<String>((ref) {
  return ref.watch(errorReporterProvider).messages;
});

/// Live count of local changes not yet exported to a sync bundle. Drives the
/// sync status badge in the navigation shell.
final pendingChangesProvider = StreamProvider<int>((ref) {
  final db = ref.watch(databaseProvider);
  final countExpr = db.changeLog.id.count();
  final query = db.selectOnly(db.changeLog)
    ..addColumns([countExpr])
    ..where(db.changeLog.exported.equals(false));
  return query.map((row) => row.read(countExpr) ?? 0).watchSingle();
});

/// The single company-settings row (id = 'default'), reactive to edits/sync.
final companySettingsStreamProvider = StreamProvider<CompanySetting?>((ref) {
  final db = ref.watch(databaseProvider);
  return (db.select(db.companySettings)
        ..where((t) => t.id.equals('default'))
        ..limit(1))
      .watchSingleOrNull();
});

/// App-wide money formatter, derived from the company currency (defaults to USD
/// until settings load), so switching to IDR shows "Rp" everywhere.
final moneyFormatProvider = Provider<MoneyFormat>((ref) {
  final settings = ref.watch(companySettingsStreamProvider).value;
  if (settings == null) return const MoneyFormat();
  return MoneyFormat.forCurrency(settings.currency, settings.currencyScale);
});

/// Currency minor-unit scale. Uses the reactive settings when available, else
/// the value loaded at startup — so it is correct even inside `initState`
/// (where the settings stream may not have emitted yet). Critical for parsing
/// money input at the right scale (e.g. IDR = 0, USD = 2).
final currencyScaleProvider = Provider<int>((ref) {
  final settings = ref.watch(companySettingsStreamProvider).value;
  return settings?.currencyScale ??
      ref.watch(appServicesProvider).currencyScale;
});
