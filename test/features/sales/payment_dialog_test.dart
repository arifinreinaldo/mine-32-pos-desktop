import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mine32_pos/core/database/app_database.dart';
import 'package:mine32_pos/core/di/app_services.dart';
import 'package:mine32_pos/core/di/providers.dart';
import 'package:mine32_pos/core/money/money.dart';
import 'package:mine32_pos/core/time/clock.dart';
import 'package:mine32_pos/features/sales/domain/cart.dart';
import 'package:mine32_pos/features/sales/presentation/payment_dialog.dart';

void main() {
  testWidgets('payment dialog tolerates invalid cash input (no crash)', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(900, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final services = await AppServices.initialize(
      database: AppDatabase(NativeDatabase.memory()),
      clock: MutableClock(1000),
    );
    addTearDown(services.dispose);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [appServicesProvider.overrideWithValue(services)],
        child: const MaterialApp(
          home: Scaffold(
            body: PaymentDialog(
              lines: [
                CartLine(
                  variantId: 'v1',
                  sku: 'BP-1',
                  name: 'Brake Pad',
                  unitPrice: Money(2500),
                  unitCost: Money(1500),
                ),
              ],
              total: Money(2500),
            ),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 200));

    // Typing a non-numeric value must not throw during build.
    await tester.enterText(find.byType(TextField).first, '12a');
    await tester.pump(const Duration(milliseconds: 200));

    expect(tester.takeException(), isNull);
    expect(find.text('Take payment'), findsOneWidget);

    // Invalid tender => Complete is disabled.
    final complete = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Complete sale'),
    );
    expect(complete.onPressed, isNull);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 300));
  });
}
