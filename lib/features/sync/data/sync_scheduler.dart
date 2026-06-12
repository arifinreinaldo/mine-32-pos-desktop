import 'dart:async';

/// Runs sync automatically on a fixed interval. Polling rather than
/// file-watching: the shared folder is typically cloud-synced (Drive/Dropbox/
/// SMB), where file-system events are unreliable or absent, and a periodic
/// pull-merge is exactly as correct.
///
/// Generic over its callbacks so it can be unit-tested with plain functions:
/// [shouldRun] gates each tick (e.g. "is a folder configured?") and [run]
/// performs the sync. Failures are swallowed — offline-first means a failed
/// pass simply retries on the next tick.
class SyncScheduler {
  final Future<bool> Function() shouldRun;
  final Future<void> Function() run;
  final Duration interval;

  Timer? _timer;
  bool _busy = false;

  SyncScheduler({
    required this.shouldRun,
    required this.run,
    this.interval = const Duration(minutes: 5),
  });

  bool get isRunning => _timer != null;

  /// Begin ticking every [interval]. Also fires one immediate tick so a
  /// configured device converges right after launch, not minutes later.
  void start() {
    if (_timer != null) return;
    _timer = Timer.periodic(interval, (_) => tick());
    unawaited(tick());
  }

  /// One guarded pass. Never overlaps a pass still in flight, and never
  /// throws — a failure waits for the next tick.
  Future<void> tick() async {
    if (_busy) return;
    _busy = true;
    try {
      if (await shouldRun()) {
        await run();
      }
    } catch (_) {
      // Folder unreachable / transient IO — retry on the next tick.
    } finally {
      _busy = false;
    }
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
  }
}
