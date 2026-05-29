import 'package:flutter_riverpod/flutter_riverpod.dart';

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
