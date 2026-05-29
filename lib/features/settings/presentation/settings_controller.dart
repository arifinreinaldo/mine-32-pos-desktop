import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/di/providers.dart';
import '../data/settings_repository.dart';

final settingsRepositoryProvider = Provider<SettingsRepository>((ref) {
  final services = ref.watch(appServicesProvider);
  return SettingsRepository(
    db: services.db,
    changeLog: services.changeLog,
    hlcService: services.hlc,
    clock: services.clock,
  );
});
