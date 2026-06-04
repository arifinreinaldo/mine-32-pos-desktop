import 'package:flutter_test/flutter_test.dart';
import 'package:mine32_pos/core/errors/app_error_reporter.dart';

void main() {
  group('AppErrorReporter.friendlyMessage', () {
    test('StateError uses its (already human) message', () {
      expect(
        AppErrorReporter.friendlyMessage(StateError('Unbalanced journal')),
        'Unbalanced journal',
      );
    });

    test('FormatException is prefixed', () {
      expect(
        AppErrorReporter.friendlyMessage(const FormatException('bad number')),
        'Invalid input: bad number',
      );
    });

    test('long generic errors are truncated with an ellipsis', () {
      final msg = AppErrorReporter.friendlyMessage(Exception('x' * 500));
      expect(msg.length, lessThanOrEqualTo(201));
      expect(msg.endsWith('…'), isTrue);
    });
  });

  test('report() emits a friendly message on the stream', () async {
    final reporter = AppErrorReporter();
    addTearDown(reporter.dispose);
    final first = reporter.messages.first;
    reporter.report(StateError('boom'));
    expect(await first, 'boom');
  });

  test('report() after dispose is a no-op', () {
    final reporter = AppErrorReporter()..dispose();
    expect(() => reporter.report(StateError('x')), returnsNormally);
  });
}
