import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'sync_controller.dart';

class SyncScreen extends ConsumerStatefulWidget {
  const SyncScreen({super.key});

  @override
  ConsumerState<SyncScreen> createState() => _SyncScreenState();
}

class _SyncScreenState extends ConsumerState<SyncScreen> {
  bool _busy = false;

  Future<void> _chooseFolder() async {
    final path = await FilePicker.getDirectoryPath(
      dialogTitle: 'Choose a shared sync folder',
    );
    if (path != null) {
      await ref.read(syncControllerProvider.notifier).setFolder(path);
    }
  }

  Future<void> _syncNow() async {
    setState(() => _busy = true);
    try {
      final message = await ref.read(syncControllerProvider.notifier).syncNow();
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(message)));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Sync failed: $e')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final info = ref.watch(syncControllerProvider);

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Sync', style: theme.textTheme.headlineSmall),
          const SizedBox(height: 16),
          Card(
            color: theme.colorScheme.surfaceContainerHighest,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Icon(Icons.info_outline, color: theme.colorScheme.primary),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Serverless sync. Point every device at the same shared '
                      'folder (OneDrive, Google Drive, Dropbox or a network '
                      'share). Changes are exchanged as files — no server, works '
                      'offline; sync whenever the folder is reachable.',
                      style: theme.textTheme.bodyMedium,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Expanded(
            child: info.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('Error: $e')),
              data: (data) => _SyncBody(
                info: data,
                busy: _busy,
                onChooseFolder: _chooseFolder,
                onSyncNow: data.configured && !_busy ? _syncNow : null,
                onRefresh: () =>
                    ref.read(syncControllerProvider.notifier).refresh(),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SyncBody extends StatelessWidget {
  final SyncInfo info;
  final bool busy;
  final VoidCallback onChooseFolder;
  final VoidCallback? onSyncNow;
  final VoidCallback onRefresh;
  const _SyncBody({
    required this.info,
    required this.busy,
    required this.onChooseFolder,
    required this.onSyncNow,
    required this.onRefresh,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _row(theme, 'This device', info.deviceId),
                const Divider(),
                _row(theme, 'Shared folder', info.folder ?? 'Not configured'),
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerLeft,
                  child: OutlinedButton.icon(
                    onPressed: onChooseFolder,
                    icon: const Icon(Icons.folder_open_outlined),
                    label: Text(
                      info.configured ? 'Change folder' : 'Choose folder',
                    ),
                  ),
                ),
                const Divider(),
                _row(theme, 'Pending changes', '${info.pending}'),
                _row(theme, 'Last sync', info.lastRun ?? 'Never'),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            FilledButton.icon(
              onPressed: onSyncNow,
              icon: busy
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.sync),
              label: Text(busy ? 'Syncing…' : 'Sync now'),
            ),
            const SizedBox(width: 12),
            TextButton(onPressed: onRefresh, child: const Text('Refresh')),
            const SizedBox(width: 12),
            Text(
              info.configured
                  ? 'Auto-sync runs every 5 minutes.'
                  : 'Choose a shared folder to enable sync.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
        if (info.history.isNotEmpty) ...[
          const SizedBox(height: 24),
          Text('Recent syncs', style: theme.textTheme.titleSmall),
          const SizedBox(height: 4),
          for (final run in info.history.take(10))
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(
                children: [
                  SizedBox(
                    width: 160,
                    child: Text(
                      _runTime(run.ranAtMs),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                  Text(
                    run.exported == 0 && run.imported == 0
                        ? 'up to date'
                        : '↑ ${run.exported} sent · ↓ ${run.imported} received',
                    style: theme.textTheme.bodySmall,
                  ),
                ],
              ),
            ),
        ],
      ],
    );
  }

  static String _runTime(int ms) {
    final d = DateTime.fromMillisecondsSinceEpoch(ms);
    String two(int n) => n.toString().padLeft(2, '0');
    return '${d.year}-${two(d.month)}-${two(d.day)} ${two(d.hour)}:${two(d.minute)}';
  }

  Widget _row(ThemeData theme, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 160,
            child: Text(
              label,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          Expanded(child: Text(value, style: theme.textTheme.bodyMedium)),
        ],
      ),
    );
  }
}
