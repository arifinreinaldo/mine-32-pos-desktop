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
import 'package:mine32_pos/features/catalog/presentation/catalog_screen.dart';

void main() {
  testWidgets('catalog screen lists a saved part', (tester) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final services = await AppServices.initialize(
      database: AppDatabase(NativeDatabase.memory()),
      clock: MutableClock(1000),
    );
    addTearDown(services.dispose);

    final repo = CatalogRepository(
      db: services.db,
      changeLog: services.changeLog,
      hlcService: services.hlc,
      clock: services.clock,
    );
    await repo.savePart(
      const PartDraft(
        name: 'Brake Pad Set',
        sku: 'BP-100',
        brandName: 'Bosch',
        price: Money(2500),
        cost: Money(1500),
        coreCharge: Money(0),
      ),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [appServicesProvider.overrideWithValue(services)],
        child: const MaterialApp(home: Scaffold(body: CatalogScreen())),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('BP-100'), findsOneWidget);
    expect(find.text('Brake Pad Set'), findsOneWidget);
    expect(find.text('Bosch'), findsOneWidget);
    expect(find.text(r'$25.00'), findsOneWidget);

    // Unmount so the Riverpod/Drift stream subscription is cancelled, then pump
    // to flush Drift's zero-duration stream-close timer (otherwise testWidgets
    // reports it as a pending timer at teardown).
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 500));
  });
}
