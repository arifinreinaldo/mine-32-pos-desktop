import 'package:flutter_test/flutter_test.dart';
import 'package:mine32_pos/core/result/app_failure.dart';
import 'package:mine32_pos/core/result/result.dart';

void main() {
  group('Result', () {
    test('Ok holds value', () {
      const r = Ok<int>(42);
      expect(r.isOk, isTrue);
      expect(r.valueOrNull, 42);
      expect(r.failureOrNull, isNull);
    });

    test('Err holds failure', () {
      const r = Err<int>(NotFoundFailure('nope'));
      expect(r.isErr, isTrue);
      expect(r.valueOrNull, isNull);
      expect(r.failureOrNull, isA<NotFoundFailure>());
    });

    test('fold', () {
      const Result<int> ok = Ok(2);
      const Result<int> err = Err(StorageFailure('x'));
      expect(ok.fold((v) => v * 10, (f) => -1), 20);
      expect(err.fold((v) => v * 10, (f) => -1), -1);
    });

    test('map transforms Ok only', () {
      const Result<int> ok = Ok(2);
      expect(ok.map((v) => v + 1).valueOrNull, 3);
      const Result<int> err = Err(StorageFailure('x'));
      expect(err.map((v) => v + 1).isErr, isTrue);
    });

    test('getOrElse returns fallback on Err', () {
      const Result<int> err = Err(StorageFailure('x'));
      expect(err.getOrElse((_) => 99), 99);
    });
  });
}
