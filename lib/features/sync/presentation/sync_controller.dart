import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/di/providers.dart';
import '../data/sync_service.dart';

class SyncInfo {
  final String deviceId;
  final String? folder;
  final int pending;
  final String? lastRun;
  final List<SyncRun> history;
  const SyncInfo({
    required this.deviceId,
    required this.folder,
    required this.pending,
    required this.lastRun,
    this.history = const [],
  });

  bool get configured => folder != null && folder!.isNotEmpty;
}

final syncServiceProvider = Provider<SyncService>(
  (ref) => SyncService(ref.watch(appServicesProvider)),
);

class SyncController extends AsyncNotifier<SyncInfo> {
  SyncService get _service => ref.read(syncServiceProvider);

  @override
  Future<SyncInfo> build() => _load();

  Future<SyncInfo> _load() async {
    return SyncInfo(
      deviceId: ref.read(appServicesProvider).deviceId,
      folder: await _service.folderPath(),
      pending: await _service.pendingCount(),
      lastRun: await _service.lastRun(),
      history: await _service.recentRuns(),
    );
  }

  Future<void> setFolder(String path) async {
    await _service.setFolderPath(path);
    state = AsyncData(await _load());
  }

  /// Runs a sync pass; returns a human summary for the caller to surface.
  Future<String> syncNow() async {
    final result = await _service.syncNow();
    state = AsyncData(await _load());
    return 'Sent ${result.exported}, received ${result.imported}';
  }

  Future<void> refresh() async {
    state = AsyncData(await _load());
  }
}

final syncControllerProvider = AsyncNotifierProvider<SyncController, SyncInfo>(
  SyncController.new,
);
