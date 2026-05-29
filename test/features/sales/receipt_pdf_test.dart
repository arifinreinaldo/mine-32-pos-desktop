import 'package:flutter_test/flutter_test.dart';
import 'package:mine32_pos/features/sales/data/receipt_pdf.dart';
import 'package:mine32_pos/features/sales/domain/receipt.dart';

void main() {
  test('buildReceiptPdf produces a non-empty PDF document', () async {
    final bytes = await buildReceiptPdf(
      const ReceiptData(
        companyName: 'Mine32 Auto Parts',
        address: 'Jl. Merdeka 1',
        npwp: '01.234.567.8-901.000',
        number: 'S-000001',
        dateMs: 0,
        lines: [
          ReceiptLine(
            name: 'Brake Pad Set',
            qty: 2,
            unitPrice: r'$25.00',
            lineTotal: r'$50.00',
          ),
        ],
        dpp: r'$45.05',
        ppn: r'$4.95',
        total: r'$50.00',
        paid: r'$50.00',
        change: r'$0.00',
        footer: 'Goods sold are not returnable',
      ),
    );

    expect(bytes.length, greaterThan(200));
    // PDF files start with the "%PDF" magic header.
    expect(String.fromCharCodes(bytes.take(4)), '%PDF');
  });
}
