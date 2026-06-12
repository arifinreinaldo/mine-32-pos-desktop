import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mine32_pos/core/database/app_database.dart';
import 'package:mine32_pos/core/money/money.dart';
import 'package:mine32_pos/core/sync/change_log_writer.dart';
import 'package:mine32_pos/core/sync/hlc_service.dart';
import 'package:mine32_pos/core/time/clock.dart';
import 'package:mine32_pos/features/accounting/data/accounting_repository.dart';
import 'package:mine32_pos/features/accounting/domain/coretax_xml.dart';
import 'package:mine32_pos/features/catalog/data/catalog_repository.dart';
import 'package:mine32_pos/features/catalog/domain/part_draft.dart';
import 'package:mine32_pos/features/inventory/data/inventory_repository.dart';
import 'package:mine32_pos/features/inventory/domain/movement_reason.dart';
import 'package:mine32_pos/features/sales/data/sales_repository.dart';
import 'package:mine32_pos/features/sales/domain/cart.dart';

void main() {
  group('buildCoreTaxXml', () {
    test('emits the TaxInvoiceBulk structure with line detail', () {
      final xml = buildCoreTaxXml(
        sellerTin: '0123456789012345',
        scale: 0,
        invoices: [
          FakturXmlInvoice(
            dateMs: DateTime.utc(2026, 1, 31).millisecondsSinceEpoch,
            refNumber: 'S-000001',
            buyerName: 'Bengkel Maju',
            buyerNpwp: '1112223334445556',
            lines: const [
              FakturXmlLine(
                name: 'Brake Pad',
                qty: 2,
                unitPriceMinor: 11100,
                dppMinor: 20000,
                ppnMinor: 2200,
              ),
            ],
          ),
        ],
      );

      expect(xml, contains('<TaxInvoiceBulk>'));
      expect(xml, contains('<TIN>0123456789012345</TIN>'));
      expect(xml, contains('<TaxInvoiceDate>2026-01-31</TaxInvoiceDate>'));
      expect(xml, contains('<RefDesc>S-000001</RefDesc>'));
      expect(xml, contains('<BuyerTin>1112223334445556</BuyerTin>'));
      expect(xml, contains('<BuyerName>Bengkel Maju</BuyerName>'));
      expect(xml, contains('<Name>Brake Pad</Name>'));
      expect(xml, contains('<Qty>2</Qty>'));
      expect(xml, contains('<TaxBase>20000</TaxBase>'));
      expect(xml, contains('<VAT>2200</VAT>'));
      expect(xml, contains('<VATRate>11</VATRate>')); // 2200/20000
    });

    test('walk-in buyer gets the 16-zero end-consumer TIN', () {
      final xml = buildCoreTaxXml(
        sellerTin: 'SELLER',
        invoices: [
          FakturXmlInvoice(
            dateMs: DateTime.utc(2026, 2, 1).millisecondsSinceEpoch,
            refNumber: 'S-2',
            lines: const [
              FakturXmlLine(
                name: 'Oil Filter',
                qty: 1,
                unitPriceMinor: 45000,
                dppMinor: 45000,
                ppnMinor: 0,
              ),
            ],
          ),
        ],
      );
      expect(xml, contains('<BuyerTin>$coreTaxEndConsumerTin</BuyerTin>'));
      expect(xml, contains('<BuyerName>Umum</BuyerName>'));
      expect(xml, contains('<VATRate>0</VATRate>'));
    });

    test('escapes XML-special characters in names', () {
      final xml = buildCoreTaxXml(
        sellerTin: 'T',
        invoices: [
          FakturXmlInvoice(
            dateMs: DateTime.utc(2026, 3, 1).millisecondsSinceEpoch,
            refNumber: 'S-3',
            buyerName: 'PT A & B <Parts>',
            lines: const [
              FakturXmlLine(
                name: 'Wiper 22" & clip',
                qty: 1,
                unitPriceMinor: 100,
                dppMinor: 100,
                ppnMinor: 11,
              ),
            ],
          ),
        ],
      );
      expect(xml, contains('PT A &amp; B &lt;Parts&gt;'));
      expect(xml, contains('Wiper 22&quot; &amp; clip'));
      expect(xml, isNot(contains('& B <Parts>')));
    });
  });

  test(
    'fakturXmlInvoicesForPeriod builds one invoice per sale with lines',
    () async {
      final db = AppDatabase(NativeDatabase.memory());
      final clock = MutableClock(1000);
      final hlc = HlcService(db, clock, 'dev');
      await hlc.load();
      final changeLog = ChangeLogWriter(db, 'dev');
      final accounting = AccountingRepository(
        db: db,
        changeLog: changeLog,
        hlcService: hlc,
        clock: clock,
      );
      await accounting.seedDefaults();
      final catalog = CatalogRepository(
        db: db,
        changeLog: changeLog,
        hlcService: hlc,
        clock: clock,
      );
      final inventory = InventoryRepository(
        db: db,
        changeLog: changeLog,
        hlcService: hlc,
        clock: clock,
      );
      final sales = SalesRepository(
        db: db,
        changeLog: changeLog,
        hlcService: hlc,
        clock: clock,
        inventory: inventory,
        accounting: accounting,
      );

      final variantId = await catalog.savePart(
        const PartDraft(
          name: 'Brake Pad',
          sku: 'BP-1',
          price: Money(11100),
          cost: Money(6000),
          coreCharge: Money(0),
        ),
      );
      await inventory.addMovement(
        variantId: variantId,
        locationId: 'L1',
        qty: 10,
        reason: MovementReason.purchase,
      );
      await sales.completeSale(
        lines: [
          CartLine(
            variantId: variantId,
            sku: 'BP-1',
            name: 'Brake Pad',
            unitPrice: const Money(11100),
            unitCost: const Money(6000),
            qty: 2,
          ),
        ],
        locationId: 'L1',
        tendered: const Money(22200),
        taxBasisPoints: 1100,
        buyerName: 'Bengkel Maju',
        buyerNpwp: '123',
      );

      final invoices = await accounting.fakturXmlInvoicesForPeriod();
      expect(invoices, hasLength(1));
      final inv = invoices.single;
      expect(inv.buyerName, 'Bengkel Maju');
      expect(inv.lines, hasLength(1));
      final line = inv.lines.single;
      expect(line.qty, 2);
      // Line DPP + PPN reconstruct the inclusive line total (22200 = 20000+2200).
      expect(line.dppMinor + line.ppnMinor, 22200);
      expect(line.ppnMinor, 2200);

      // And the full document renders.
      final xml = buildCoreTaxXml(sellerTin: 'TIN', invoices: invoices);
      expect(xml, contains('<RefDesc>${inv.refNumber}</RefDesc>'));

      await db.close();
    },
  );
}
