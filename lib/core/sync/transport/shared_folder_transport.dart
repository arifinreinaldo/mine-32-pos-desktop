import 'dart:io';

import 'package:path/path.dart' as p;

import 'sync_transport.dart';

/// Serverless transport over a shared/cloud-synced directory (OneDrive, Dropbox,
/// Google Drive, a Windows network share, or a USB stick). Each device writes
/// bundles into `<root>/<deviceId>/` and reads peers' sibling folders. No server.
class SharedFolderTransport implements SyncTransport {
  final String rootPath;
  @override
  final String selfDeviceId;

  SharedFolderTransport({required this.rootPath, required this.selfDeviceId});

  Directory get _selfDir => Directory(p.join(rootPath, selfDeviceId));

  @override
  Future<void> putBundle(String name, List<int> bytes) async {
    await _selfDir.create(recursive: true);
    // Write to a temp file then rename so peers never read a partial bundle.
    final tmp = File(p.join(_selfDir.path, '$name.part'));
    await tmp.writeAsBytes(bytes, flush: true);
    await tmp.rename(p.join(_selfDir.path, name));
  }

  @override
  Future<List<BundleRef>> listPeerBundles() async {
    final root = Directory(rootPath);
    if (!root.existsSync()) return const [];
    final refs = <BundleRef>[];
    await for (final entity in root.list(followLinks: false)) {
      if (entity is! Directory) continue;
      final deviceId = p.basename(entity.path);
      if (deviceId == selfDeviceId) continue;
      await for (final file in entity.list(followLinks: false)) {
        if (file is! File) continue;
        final name = p.basename(file.path);
        if (!name.endsWith('.json')) continue;
        refs.add(BundleRef(deviceId, name));
      }
    }
    return refs;
  }

  @override
  Future<List<int>> getBundle(BundleRef ref) async {
    final file = File(p.join(rootPath, ref.deviceId, ref.name));
    return file.readAsBytes();
  }
}
