import 'package:flutter_test/flutter_test.dart';
import 'package:mine32_pos/features/accounting/domain/tax_math.dart';

void main() {
  group('TaxMath', () {
    test('inclusive split (PPN 11%) of a tax-inclusive total', () {
      final a = TaxMath.split(
        amountMinor: 1110,
        basisPoints: 1100,
        inclusive: true,
      );
      expect(a.baseMinor, 1000);
      expect(a.taxMinor, 110);
      expect(a.totalMinor, 1110);
    });

    test('exclusive split adds tax on top', () {
      final a = TaxMath.split(
        amountMinor: 1000,
        basisPoints: 1100,
        inclusive: false,
      );
      expect(a.baseMinor, 1000);
      expect(a.taxMinor, 110);
      expect(a.totalMinor, 1110);
    });

    test('zero rate is a no-op', () {
      final a = TaxMath.split(
        amountMinor: 999,
        basisPoints: 0,
        inclusive: true,
      );
      expect(a.baseMinor, 999);
      expect(a.taxMinor, 0);
      expect(a.totalMinor, 999);
    });

    test('inclusive split rounds half-up and base+tax==total', () {
      final a = TaxMath.split(
        amountMinor: 1000,
        basisPoints: 1100,
        inclusive: true,
      );
      expect(a.baseMinor + a.taxMinor, 1000);
      expect(a.baseMinor, 901); // 1000 * 10000/11100 ≈ 900.9 -> 901
      expect(a.taxMinor, 99);
    });
  });
}
