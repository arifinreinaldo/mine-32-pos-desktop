import 'package:flutter_test/flutter_test.dart';
import 'package:mine32_pos/core/money/money.dart';
import 'package:mine32_pos/shared/formatters/money_format.dart';

void main() {
  group('MoneyFormat', () {
    test('USD with thousands grouping', () {
      expect(const MoneyFormat().format(Money(123456)), r'$1,234.56');
    });

    test('IDR (scale 0) shows Rp and no decimals', () {
      expect(
        MoneyFormat.forCurrency('IDR', 0).format(Money(50000)),
        'Rp 50,000',
      );
    });

    test('negative amounts keep the sign before the symbol', () {
      expect(const MoneyFormat().format(Money(-5)), r'-$0.05');
    });

    test('unknown currency falls back to its code', () {
      expect(
        MoneyFormat.forCurrency('JPY', 0).format(Money(1000)),
        'JPY 1,000',
      );
    });
  });
}
