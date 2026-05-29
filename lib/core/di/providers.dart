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

/// App-wide money formatter. (Currency symbol will be sourced from company
/// settings in a later milestone.)
final moneyFormatProvider = Provider<MoneyFormat>((ref) => const MoneyFormat());
