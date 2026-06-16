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
import 'package:mine32_pos/features/inventory/presentation/stock_count_dialog.dart';

void main() {
  testWidgets('counting posts the difference as a stock adjustment', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1000, 900);
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
    final loc = await inventory.ensureDefaultLocation();
    final variantId = await catalog.savePart(
      const PartDraft(
        name: 'Brake Pad',
        sku: 'BP-1',
        price: Money(2500),
        cost: Money(1500),
        coreCharge: Money(0),
      ),
    );
    await inventory.addMovement(
      variantId: variantId,
      locationId: loc,
      qty: 10,
      reason: MovementReason.purchase,
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [appServicesProvider.overrideWithValue(services)],
        child: const MaterialApp(home: Scaffold(body: StockCountDialog())),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    // The on-hand (10) is shown and the counted field is prefilled with it.
    expect(find.text('10'), findsWidgets);
    expect(find.text('BP-1 · Brake Pad'), findsOneWidget);

    // Count it as 7 and post.
    await tester.enterText(find.byType(TextField), '7');
    await tester.tap(find.widgetWithText(FilledButton, 'Post count'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(await inventory.onHand(variantId, loc), 7);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 500));
  });
}
