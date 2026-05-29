import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mine32_pos/core/database/app_database.dart';
import 'package:mine32_pos/core/di/app_services.dart';
import 'package:mine32_pos/core/di/providers.dart';
import 'package:mine32_pos/core/money/money.dart';
import 'package:mine32_pos/core/time/clock.dart';
import 'package:mine32_pos/features/catalog/data/catalog_repository.dart';
import 'package:mine32_pos/features/catalog/domain/part_draft.dart';
import 'package:mine32_pos/features/dashboard/presentation/dashboard_screen.dart';
import 'package:mine32_pos/features/inventory/data/inventory_repository.dart';
import 'package:mine32_pos/features/inventory/domain/movement_reason.dart';
import 'package:mine32_pos/features/sales/data/sales_repository.dart';
import 'package:mine32_pos/features/sales/domain/cart.dart';

Future<void> _settle(WidgetTester tester, [int frames = 8]) async {
  for (var i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 120));
  }
}

void main() {
  testWidgets("dashboard shows today's revenue and recent sale", (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1500, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final services = await AppServices.initialize(
      database: AppDatabase(NativeDatabase.memory()),
      clock: MutableClock(DateTime.now().millisecondsSinceEpoch),
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
    final sales = SalesRepository(
      db: services.db,
      changeLog: services.changeLog,
      hlcService: services.hlc,
      clock: services.clock,
      inventory: inventory,
    );

    final variantId = await catalog.savePart(
      const PartDraft(
        name: 'Brake Pad',
        sku: 'BP-1',
        price: Money(5000),
        cost: Money(3000),
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
          unitPrice: const Money(5000),
          unitCost: const Money(3000),
        ),
      ],
      locationId: 'L1',
      tendered: const Money(5000),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [appServicesProvider.overrideWithValue(services)],
        child: const MaterialApp(home: Scaffold(body: DashboardScreen())),
      ),
    );
    await _settle(tester);

    expect(find.text("Today's revenue"), findsOneWidget);
    expect(find.text(r'$50.00'), findsWidgets);
    expect(find.text('S-000001'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 500));
  });
}
