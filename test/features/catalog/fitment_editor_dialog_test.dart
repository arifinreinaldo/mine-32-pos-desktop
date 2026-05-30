import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mine32_pos/core/database/app_database.dart';
import 'package:mine32_pos/core/di/app_services.dart';
import 'package:mine32_pos/core/di/providers.dart';
import 'package:mine32_pos/core/money/money.dart';
import 'package:mine32_pos/core/time/clock.dart';
import 'package:mine32_pos/features/catalog/data/auto_parts_repository.dart';
import 'package:mine32_pos/features/catalog/data/catalog_repository.dart';
import 'package:mine32_pos/features/catalog/domain/auto_parts_models.dart';
import 'package:mine32_pos/features/catalog/domain/part_draft.dart';
import 'package:mine32_pos/features/catalog/presentation/fitment_editor_dialog.dart';

Future<
  ({
    AppServices services,
    CatalogRepository catalog,
    AutoPartsRepository auto,
    String variantId,
  })
>
_seed() async {
  final services = await AppServices.initialize(
    database: AppDatabase(NativeDatabase.memory()),
    clock: MutableClock(1000),
  );
  final catalog = CatalogRepository(
    db: services.db,
    changeLog: services.changeLog,
    hlcService: services.hlc,
    clock: services.clock,
  );
  final auto = AutoPartsRepository(
    db: services.db,
    changeLog: services.changeLog,
    hlcService: services.hlc,
    clock: services.clock,
  );
  final variantId = await catalog.savePart(
    const PartDraft(
      name: 'Oil Filter',
      sku: 'OF-1',
      price: Money(900),
      cost: Money(500),
      coreCharge: Money(0),
    ),
  );
  return (
    services: services,
    catalog: catalog,
    auto: auto,
    variantId: variantId,
  );
}

Widget _host(AppServices services, String variantId) {
  return ProviderScope(
    overrides: [appServicesProvider.overrideWithValue(services)],
    child: MaterialApp(
      home: Scaffold(
        body: FitmentEditorDialog(
          variantId: variantId,
          partLabel: 'OF-1 · Oil Filter',
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('shows linked vehicle and cross-reference', (tester) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final s = await _seed();
    addTearDown(s.services.dispose);

    final vehicleId = await s.auto.findOrCreateVehicle(
      const VehicleDraft(
        make: 'Toyota',
        model: 'Avanza',
        yearFrom: 2015,
        yearTo: 2021,
        engine: '1.3L',
      ),
    );
    await s.auto.addFitment(variantId: s.variantId, vehicleId: vehicleId);
    await s.auto.addCrossReference(
      variantId: s.variantId,
      otherNumber: '90915-YZZE1',
      otherBrand: 'Toyota',
      refType: 'oem',
    );

    await tester.pumpWidget(_host(s.services, s.variantId));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('Fits vehicles'), findsOneWidget);
    expect(find.text('Toyota Avanza 2015-2021 1.3L'), findsOneWidget);
    expect(find.text('90915-YZZE1'), findsOneWidget);
    expect(find.text('Toyota · OEM'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 500));
  });

  testWidgets('adding a cross-reference through the UI persists it', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final s = await _seed();
    addTearDown(s.services.dispose);

    await tester.pumpWidget(_host(s.services, s.variantId));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('No cross-references yet.'), findsOneWidget);

    // Open the cross-reference "Add" (second Add button) and fill the number.
    await tester.tap(find.widgetWithText(TextButton, 'Add').at(1));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField).first, 'GENUINE-123');
    await tester.tap(find.widgetWithText(FilledButton, 'Add'));
    await tester.pumpAndSettle();

    // It now shows in the list and is persisted in the repository.
    expect(find.text('GENUINE-123'), findsOneWidget);
    expect(
      await s.auto.lookupVariantIdsByNumber('GENUINE-123'),
      contains(s.variantId),
    );

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 500));
  });
}
