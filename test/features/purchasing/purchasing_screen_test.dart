import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mine32_pos/core/database/app_database.dart';
import 'package:mine32_pos/core/di/app_services.dart';
import 'package:mine32_pos/core/di/providers.dart';
import 'package:mine32_pos/core/time/clock.dart';
import 'package:mine32_pos/features/accounting/data/accounting_repository.dart';
import 'package:mine32_pos/features/inventory/data/inventory_repository.dart';
import 'package:mine32_pos/features/purchasing/data/purchasing_repository.dart';
import 'package:mine32_pos/features/purchasing/domain/purchasing_models.dart';
import 'package:mine32_pos/features/purchasing/presentation/purchasing_screen.dart';

void main() {
  testWidgets('purchasing screen lists a supplier', (tester) async {
    tester.view.physicalSize = const Size(1400, 950);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final services = await AppServices.initialize(
      database: AppDatabase(NativeDatabase.memory()),
      clock: MutableClock(1000),
    );
    addTearDown(services.dispose);

    final purchasing = PurchasingRepository(
      db: services.db,
      changeLog: services.changeLog,
      hlcService: services.hlc,
      clock: services.clock,
      inventory: InventoryRepository(
        db: services.db,
        changeLog: services.changeLog,
        hlcService: services.hlc,
        clock: services.clock,
      ),
      accounting: AccountingRepository(
        db: services.db,
        changeLog: services.changeLog,
        hlcService: services.hlc,
        clock: services.clock,
      ),
    );
    await purchasing.saveSupplier(
      const SupplierDraft(name: 'PT Sumber Parts', phone: '021-555'),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [appServicesProvider.overrideWithValue(services)],
        child: const MaterialApp(home: Scaffold(body: PurchasingScreen())),
      ),
    );
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 120));
    }

    expect(find.text('PT Sumber Parts'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 500));
  });
}
