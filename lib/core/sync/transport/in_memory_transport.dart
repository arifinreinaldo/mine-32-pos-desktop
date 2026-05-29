import 'sync_transport.dart';

/// Shared backing store simulating a sync folder; multiple [InMemoryTransport]
/// instances (one per device) point at the same [InMemoryFolder] in tests.
class InMemoryFolder {
  /// deviceId -> (bundleName -> bytes)
  final Map<String, Map<String, List<int>>> data = {};
}

class InMemoryTransport implements SyncTransport {
  final InMemoryFolder folder;
  @override
  final String selfDeviceId;

  InMemoryTransport(this.folder, this.selfDeviceId);

  @override
  Future<void> putBundle(String name, List<int> bytes) async {
    folder.data.putIfAbsent(selfDeviceId, () => {})[name] = bytes;
  }

  @override
  Future<List<BundleRef>> listPeerBundles() async {
    final refs = <BundleRef>[];
    for (final entry in folder.data.entries) {
      if (entry.key == selfDeviceId) continue;
      for (final name in entry.value.keys) {
        refs.add(BundleRef(entry.key, name));
      }
    }
    return refs;
  }

  @override
  Future<List<int>> getBundle(BundleRef ref) async {
    return folder.data[ref.deviceId]![ref.name]!;
  }
}
