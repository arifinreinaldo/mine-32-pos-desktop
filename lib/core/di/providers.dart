import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../shared/formatters/money_format.dart';
import '../database/app_database.dart';
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
