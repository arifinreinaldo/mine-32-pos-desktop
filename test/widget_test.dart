import 'package:drift/native.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mine32_pos/app/app.dart';
import 'package:mine32_pos/core/database/app_database.dart';
import 'package:mine32_pos/core/di/app_services.dart';
import 'package:mine32_pos/core/di/providers.dart';
import 'package:mine32_pos/core/time/clock.dart';

void main() {
  testWidgets('app boots to the dashboard and shows the side navigation', (
    tester,
  ) async {
    // Desktop-sized window so the layout has room (and is realistic).
    tester.view.physicalSize = const Size(1400, 900);
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
        child: const MineApp(),
      ),
    );
    await tester.pumpAndSettle();

    // Brand + a couple of nav sections render.
    expect(find.text('Mine32 POS'), findsOneWidget);
    expect(find.text('Dashboard'), findsWidgets);
    expect(find.text('Catalog'), findsWidgets);
    expect(find.text('Sell'), findsWidgets);
  });
}
