import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../domain/receipt.dart';

/// Renders an 80mm thermal-style receipt PDF. Pure (returns bytes), so it can be
/// unit-tested and handed to the `printing` plugin for preview/print.
Future<Uint8List> buildReceiptPdf(ReceiptData data) {
  final doc = pw.Document();
  final date = DateTime.fromMillisecondsSinceEpoch(data.dateMs).toString();

  doc.addPage(
    pw.Page(
      pageFormat: PdfPageFormat.roll80,
      margin: const pw.EdgeInsets.all(8),
      build: (context) {
        return pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.stretch,
          children: [
            pw.Center(
              child: pw.Text(
                data.companyName,
                style: pw.TextStyle(
                  fontSize: 13,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
            ),
            if (data.address != null)
              pw.Center(
                child: pw.Text(
                  data.address!,
                  style: const pw.TextStyle(fontSize: 8),
                  textAlign: pw.TextAlign.center,
                ),
              ),
            if (data.npwp != null)
              pw.Center(
                child: pw.Text(
                  'NPWP: ${data.npwp}',
                  style: const pw.TextStyle(fontSize: 8),
                ),
              ),
            pw.SizedBox(height: 6),
            pw.Text(
              'No   : ${data.number}',
              style: const pw.TextStyle(fontSize: 9),
            ),
            pw.Text('Date : $date', style: const pw.TextStyle(fontSize: 8)),
            pw.Divider(),
            for (final l in data.lines)
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.stretch,
                children: [
                  pw.Text(l.name, style: const pw.TextStyle(fontSize: 9)),
                  pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                    children: [
                      pw.Text(
                        '${l.qty} x ${l.unitPrice}',
                        style: const pw.TextStyle(fontSize: 8),
                      ),
                      pw.Text(
                        l.lineTotal,
                        style: const pw.TextStyle(fontSize: 9),
                      ),
                    ],
                  ),
                ],
              ),
            pw.Divider(),
            if (data.dpp != null) _kv('DPP', data.dpp!),
            if (data.ppn != null) _kv('PPN', data.ppn!),
            _kv('Total', data.total, bold: true),
            _kv('Paid', data.paid),
            _kv('Change', data.change),
            pw.SizedBox(height: 8),
            if (data.footer != null)
              pw.Center(
                child: pw.Text(
                  data.footer!,
                  style: const pw.TextStyle(fontSize: 8),
                  textAlign: pw.TextAlign.center,
                ),
              ),
            pw.Center(
              child: pw.Text(
                'Thank you',
                style: const pw.TextStyle(fontSize: 9),
              ),
            ),
          ],
        );
      },
    ),
  );

  return doc.save();
}

pw.Widget _kv(String key, String value, {bool bold = false}) {
  final style = pw.TextStyle(
    fontSize: 9,
    fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
  );
  return pw.Row(
    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
    children: [
      pw.Text(key, style: style),
      pw.Text(value, style: style),
    ],
  );
}
