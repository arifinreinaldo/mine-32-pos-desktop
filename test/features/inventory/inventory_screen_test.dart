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
import 'package:mine32_pos/features/inventory/data/inventory_repository.dart';
import 'package:mine32_pos/features/inventory/domain/movement_reason.dart';
import 'package:mine32_pos/features/inventory/presentation/inventory_screen.dart';

void main() {
  testWidgets('inventory screen shows on-hand for a part', (tester) async {
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
    final variantId = await catalog.savePart(
      const PartDraft(
        name: 'Brake Pad Set',
        sku: 'BP-100',
        price: Money(2500),
        cost: Money(1500),
        coreCharge: Money(0),
      ),
    );
    await inventory.addMovement(
      variantId: variantId,
      locationId: 'L1',
      qty: 12,
      reason: MovementReason.purchase,
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [appServicesProvider.overrideWithValue(services)],
        child: const MaterialApp(home: Scaffold(body: InventoryScreen())),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('BP-100'), findsOneWidget);
    expect(find.text('12'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 500));
  });
}
