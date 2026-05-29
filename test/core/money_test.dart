import 'package:flutter_test/flutter_test.dart';
import 'package:mine32_pos/core/money/money.dart';

void main() {
  group('Money', () {
    test('fromMajor converts using exact decimal math (no float error)', () {
      expect(Money.fromMajor('12.50').minorUnits, 1250);
      expect(Money.fromMajor(0.1).minorUnits, 10);
      expect(Money.fromMajor('19.99').minorUnits, 1999);
      expect(Money.fromMajor('1', scale: 0).minorUnits, 1);
    });

    test('addition and subtraction', () {
      expect((Money(1000) + Money(250)).minorUnits, 1250);
      expect((Money(1000) - Money(250)).minorUnits, 750);
    });

    test('negation and multiplication', () {
      expect((-Money(500)).minorUnits, -500);
      expect((Money(150) * 3).minorUnits, 450);
      expect(Money(-25).abs().minorUnits, 25);
    });

    test('sum', () {
      expect(Money.sum([Money(100), Money(200), Money(300)]).minorUnits, 600);
      expect(Money.sum(const <Money>[]).minorUnits, 0);
    });

    test('comparisons and sorting', () {
      expect(Money(100) < Money(200), isTrue);
      expect(Money(200) >= Money(200), isTrue);
      final list = [Money(300), Money(100), Money(200)]..sort();
      expect(list.map((m) => m.minorUnits), [100, 200, 300]);
    });

    test('equality and hashCode include currency', () {
      expect(Money(100), Money(100));
      expect(Money(100).hashCode, Money(100).hashCode);
      expect(Money(100) == Money(100, currency: 'EUR'), isFalse);
    });

    test('toMajorString', () {
      expect(Money(1250).toMajorString(), '12.50');
      expect(Money(-5).toMajorString(), '-0.05');
      expect(Money(100).toMajorString(scale: 0), '100');
      expect(Money(5).toMajorString(), '0.05');
    });

    test('currency mismatch throws', () {
      expect(
        () => Money(1, currency: 'USD') + Money(1, currency: 'EUR'),
        throwsArgumentError,
      );
    });
  });
}
