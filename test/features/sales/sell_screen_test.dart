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
import 'package:mine32_pos/features/sales/presentation/sell_screen.dart';

/// Pump a fixed number of bounded frames (avoids pumpAndSettle, which never
/// settles while a search spinner or snackbar animation is on screen).
Future<void> _settle(WidgetTester tester, [int frames = 6]) async {
  for (var i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 120));
  }
}

void main() {
  testWidgets('sell: searching a part and tapping it fills the cart', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1500, 950);
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
    await catalog.savePart(
      const PartDraft(
        name: 'Brake Pad Set',
        sku: 'BP-100',
        price: Money(2500),
        cost: Money(1500),
        coreCharge: Money(0),
      ),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [appServicesProvider.overrideWithValue(services)],
        child: const MaterialApp(home: Scaffold(body: SellScreen())),
      ),
    );
    await _settle(tester);

    await tester.enterText(find.byType(TextField).first, 'BP-100');
    await _settle(tester);
    expect(find.text('Brake Pad Set'), findsOneWidget);

    await tester.tap(find.text('Brake Pad Set'));
    await _settle(tester);

    // Cart now shows the line and the Charge button with the total.
    expect(find.textContaining('Charge'), findsOneWidget);
    expect(find.text(r'$25.00'), findsWidgets);

    // Unmount to flush Drift's stream-close timer.
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 500));
  });

  testWidgets('sell: a per-line discount reduces the charge total', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1500, 950);
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
    await catalog.savePart(
      const PartDraft(
        name: 'Brake Pad Set',
        sku: 'BP-100',
        price: Money(2500),
        cost: Money(1500),
        coreCharge: Money(0),
      ),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [appServicesProvider.overrideWithValue(services)],
        child: const MaterialApp(home: Scaffold(body: SellScreen())),
      ),
    );
    await _settle(tester);

    await tester.enterText(find.byType(TextField).first, 'BP-100');
    await _settle(tester);
    await tester.tap(find.text('Brake Pad Set'));
    await _settle(tester);

    // Open the per-line discount dialog and apply $5 off.
    await tester.tap(find.byTooltip('Discount'));
    await _settle(tester);
    await tester.enterText(find.byType(TextField).last, '5');
    await tester.tap(find.widgetWithText(FilledButton, 'Apply'));
    await _settle(tester);

    // Charge drops from $25.00 to $20.00 and the discount is shown.
    expect(find.textContaining(r'Charge $20.00'), findsOneWidget);
    expect(find.textContaining(r'−$5.00'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 500));
  });
}
