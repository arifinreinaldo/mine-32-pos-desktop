import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mine32_pos/app/app.dart';
import 'package:mine32_pos/core/database/app_database.dart';
import 'package:mine32_pos/core/di/app_services.dart';
import 'package:mine32_pos/core/di/providers.dart';
import 'package:mine32_pos/core/errors/app_error_reporter.dart';
import 'package:mine32_pos/core/time/clock.dart';

void main() {
  testWidgets('a reported error surfaces as a snackbar', (tester) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final services = await AppServices.initialize(
      database: AppDatabase(NativeDatabase.memory()),
      clock: MutableClock(DateTime.now().millisecondsSinceEpoch),
    );
    addTearDown(services.dispose);
    final reporter = AppErrorReporter();
    addTearDown(reporter.dispose);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appServicesProvider.overrideWithValue(services),
          errorReporterProvider.overrideWithValue(reporter),
        ],
        child: const MineApp(),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    reporter.report(StateError('Unbalanced journal'));
    await tester.pump(); // deliver the stream event
    await tester.pump(
      const Duration(milliseconds: 300),
    ); // snackbar animates in

    expect(find.text('Unbalanced journal'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 500));
  });
}
