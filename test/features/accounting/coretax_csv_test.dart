import 'package:flutter_test/flutter_test.dart';
import 'package:mine32_pos/features/accounting/domain/coretax_csv.dart';

void main() {
  group('buildCoreTaxCsv', () {
    test('emits a header and a row with DPP/PPN/total in major units', () {
      final csv = buildCoreTaxCsv(const [
        FakturRow(
          number: 'S-000001',
          dateMs: 0,
          buyerName: 'PT Maju',
          buyerNpwp: '01.234.567.8-901.000',
          fakturNumber: '010.000-24.00000001',
          dppMinor: 10000,
          ppnMinor: 1100,
          totalMinor: 11100,
        ),
      ]);
      expect(csv, contains('number,date,buyer_name,buyer_npwp'));
      expect(csv, contains('S-000001'));
      expect(csv, contains('100.00')); // DPP
      expect(csv, contains('11.00')); // PPN
      expect(csv, contains('111.00')); // total
    });

    test('escapes commas in fields', () {
      final csv = buildCoreTaxCsv(const [
        FakturRow(
          number: 'S-1',
          dateMs: 0,
          buyerName: 'Maju, Jaya',
          dppMinor: 100,
          ppnMinor: 11,
          totalMinor: 111,
        ),
      ]);
      expect(csv, contains('"Maju, Jaya"'));
    });

    test('respects scale 0 (e.g. IDR)', () {
      final csv = buildCoreTaxCsv(const [
        FakturRow(
          number: 'S-1',
          dateMs: 0,
          dppMinor: 100000,
          ppnMinor: 11000,
          totalMinor: 111000,
        ),
      ], scale: 0);
      expect(csv, contains('100000,11000,111000'));
    });
  });
}
