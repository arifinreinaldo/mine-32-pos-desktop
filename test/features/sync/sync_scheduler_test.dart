import 'package:flutter_test/flutter_test.dart';
import 'package:mine32_pos/features/sync/data/sync_scheduler.dart';

void main() {
  test('start() runs immediately and then on every interval', () async {
    var runs = 0;
    final s = SyncScheduler(
      shouldRun: () async => true,
      run: () async => runs++,
      interval: const Duration(milliseconds: 20),
    );
    s.start();
    expect(s.isRunning, isTrue);
    await Future<void>.delayed(const Duration(milliseconds: 150));
    s.stop();
    expect(s.isRunning, isFalse);
    // Immediate tick + several periodic ones (generous lower bound for CI).
    expect(runs, greaterThanOrEqualTo(3));

    // After stop, no further runs.
    final after = runs;
    await Future<void>.delayed(const Duration(milliseconds: 80));
    expect(runs, after);
  });

  test('does not run while shouldRun is false', () async {
    var runs = 0;
    final s = SyncScheduler(
      shouldRun: () async => false,
      run: () async => runs++,
      interval: const Duration(milliseconds: 10),
    );
    s.start();
    await Future<void>.delayed(const Duration(milliseconds: 80));
    s.stop();
    expect(runs, 0);
  });

  test(
    'passes never overlap, even when run is slower than the interval',
    () async {
      var active = 0;
      var maxActive = 0;
      final s = SyncScheduler(
        shouldRun: () async => true,
        run: () async {
          active++;
          if (active > maxActive) maxActive = active;
          await Future<void>.delayed(const Duration(milliseconds: 40));
          active--;
        },
        interval: const Duration(milliseconds: 10),
      );
      s.start();
      await Future<void>.delayed(const Duration(milliseconds: 200));
      s.stop();
      expect(maxActive, 1);
    },
  );

  test('a throwing pass does not stop the schedule', () async {
    var calls = 0;
    final s = SyncScheduler(
      shouldRun: () async => true,
      run: () async {
        calls++;
        if (calls == 1) throw StateError('folder unreachable');
      },
      interval: const Duration(milliseconds: 15),
    );
    s.start();
    await Future<void>.delayed(const Duration(milliseconds: 120));
    s.stop();
    expect(calls, greaterThanOrEqualTo(2)); // recovered after the failure
  });

  test('start() is idempotent', () async {
    var runs = 0;
    final s = SyncScheduler(
      shouldRun: () async => true,
      run: () async => runs++,
      interval: const Duration(milliseconds: 1000),
    );
    s.start();
    s.start(); // no second timer
    await Future<void>.delayed(const Duration(milliseconds: 50));
    s.stop();
    expect(runs, 1); // just the immediate tick
  });
}
