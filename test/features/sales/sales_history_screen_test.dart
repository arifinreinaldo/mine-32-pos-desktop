import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mine32_pos/core/database/app_database.dart';
import 'package:mine32_pos/core/di/app_services.dart';
import 'package:mine32_pos/core/di/providers.dart';
import 'package:mine32_pos/core/money/money.dart';
import 'package:mine32_pos/core/time/clock.dart';
import 'package:mine32_pos/features/accounting/data/accounting_repository.dart';
import 'package:mine32_pos/features/catalog/data/catalog_repository.dart';
import 'package:mine32_pos/features/catalog/domain/part_draft.dart';
import 'package:mine32_pos/features/inventory/data/inventory_repository.dart';
import 'package:mine32_pos/features/inventory/domain/movement_reason.dart';
import 'package:mine32_pos/features/sales/data/sales_repository.dart';
import 'package:mine32_pos/features/sales/domain/cart.dart';
import 'package:mine32_pos/features/sales/presentation/sales_history_screen.dart';

void main() {
  testWidgets('lists a completed sale and shows its detail on tap', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final services = await AppServices.initialize(
      database: AppDatabase(NativeDatabase.memory()),
      clock: MutableClock(1000),
    );
    addTearDown(services.dispose);

    final catalog = CatalogRepository(
      db: services.db,
      changeLog: services.changeLog,
      hlcService: services.hlc,
      clock: services.clock,
    );
    final inventory = InventoryRepository(
      db: services.db,
      changeLog: services.changeLog,
      hlcService: services.hlc,
      clock: services.clock,
    );
    final accounting = AccountingRepository(
      db: services.db,
      changeLog: services.changeLog,
      hlcService: services.hlc,
      clock: services.clock,
    );
    final sales = SalesRepository(
      db: services.db,
      changeLog: services.changeLog,
      hlcService: services.hlc,
      clock: services.clock,
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
        ),
      ],
      locationId: 'L1',
      tendered: const Money(11100),
      taxBasisPoints: 1100,
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [appServicesProvider.overrideWithValue(services)],
        child: const MaterialApp(home: Scaffold(body: SalesHistoryScreen())),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    // Before selecting, the detail panel prompts to pick a sale.
    expect(find.text('Select a sale'), findsOneWidget);

    // Tap the (only) sale row.
    await tester.tap(find.byType(ListTile).first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    // Detail shows the line and the reprint action.
    expect(find.text('Brake Pad'), findsWidgets);
    expect(find.text('Print receipt'), findsOneWidget);
    expect(find.text('PPN'), findsOneWidget); // tax breakdown present

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 500));
  });
}
