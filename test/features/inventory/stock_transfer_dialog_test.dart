import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mine32_pos/core/database/app_database.dart';
import 'package:mine32_pos/core/di/app_services.dart';
import 'package:mine32_pos/core/di/providers.dart';
import 'package:mine32_pos/core/time/clock.dart';
import 'package:mine32_pos/features/inventory/data/inventory_repository.dart';
import 'package:mine32_pos/features/inventory/domain/movement_reason.dart';
import 'package:mine32_pos/features/inventory/domain/stock_models.dart';
import 'package:mine32_pos/features/inventory/presentation/stock_transfer_dialog.dart';

void main() {
  testWidgets('transferring through the dialog moves stock between locations', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1000, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final services = await AppServices.initialize(
      database: AppDatabase(NativeDatabase.memory()),
      clock: MutableClock(1000),
    );
    addTearDown(services.dispose);

    final repo = InventoryRepository(
      db: services.db,
      changeLog: services.changeLog,
      hlcService: services.hlc,
      clock: services.clock,
    );
    // Use the returned ids (plain futures) — awaiting a Drift watch stream in
    // the test body would hang under FakeAsync, since its first emission is
    // timer-driven and only fires on pump.
    final from = await repo.ensureDefaultLocation(); // 'Main Store'
    final to = await repo.upsertLocation(
      const LocationDraft(name: 'Warehouse'),
    );
    await repo.addMovement(
      variantId: 'V1',
      locationId: from,
      qty: 10,
      reason: MovementReason.purchase,
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [appServicesProvider.overrideWithValue(services)],
        child: const MaterialApp(
          home: Scaffold(
            body: StockTransferDialog(variantId: 'V1', label: 'V1'),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    await tester.enterText(find.byType(TextField), '4');
    await tester.tap(find.widgetWithText(FilledButton, 'Transfer'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(await repo.onHand('V1', from), 6);
    expect(await repo.onHand('V1', to), 4);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 500));
  });
}
