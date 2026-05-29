/// A bundle available from a transport, identified by its producing device and
/// file name. Names are HLC-derived and lexicographically increasing per device.
class BundleRef {
  final String deviceId;
  final String name;
  const BundleRef(this.deviceId, this.name);

  @override
  String toString() => '$deviceId/$name';
}

/// Pluggable, **serverless** exchange medium for sync bundles. The default
/// implementation is a shared/cloud-synced folder; tests use an in-memory one.
/// No implementation talks to a backend the app has to run.
abstract interface class SyncTransport {
  /// This device's id; its bundles live in its own namespace/folder.
  String get selfDeviceId;

  /// Publish one of our bundles under [name].
  Future<void> putBundle(String name, List<int> bytes);

  /// List bundles produced by *other* devices.
  Future<List<BundleRef>> listPeerBundles();

  /// Fetch the bytes for a referenced bundle.
  Future<List<int>> getBundle(BundleRef ref);
}
