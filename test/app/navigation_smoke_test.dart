import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mine32_pos/app/app.dart';
import 'package:mine32_pos/core/database/app_database.dart';
import 'package:mine32_pos/core/di/app_services.dart';
import 'package:mine32_pos/core/di/providers.dart';
import 'package:mine32_pos/core/time/clock.dart';

Future<void> _settle(WidgetTester tester, [int frames = 8]) async {
  for (var i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 120));
  }
}

void main() {
  testWidgets('every section renders without runtime errors', (tester) async {
    tester.view.physicalSize = const Size(1500, 950);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final services = await AppServices.initialize(
      database: AppDatabase(NativeDatabase.memory()),
      clock: MutableClock(DateTime.now().millisecondsSinceEpoch),
    );
    addTearDown(services.dispose);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [appServicesProvider.overrideWithValue(services)],
        child: const MineApp(),
      ),
    );
    await _settle(tester);

    // nav label -> a piece of text expected on the destination screen
    const sections = <String, String>{
      'Sell': 'Current sale',
      'Sales': 'Sales history',
      'Catalog': 'Catalog',
      'Stock': 'Stock',
      'Purchasing': 'Purchasing',
      'Customers': 'Customers',
      'Accounts': 'Chart of accounts',
      'Reports': 'Reports',
      'Sync': 'Sync',
      'Settings': 'Settings',
      'Dashboard': 'Dashboard',
    };

    for (final entry in sections.entries) {
      await tester.tap(find.widgetWithText(ListTile, entry.key).first);
      await _settle(tester);
      expect(
        tester.takeException(),
        isNull,
        reason: 'navigating to ${entry.key} threw',
      );
      expect(
        find.text(entry.value),
        findsWidgets,
        reason: '${entry.key} screen should show "${entry.value}"',
      );
    }

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 500));
  });
}
