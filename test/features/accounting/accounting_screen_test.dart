import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mine32_pos/core/database/app_database.dart';
import 'package:mine32_pos/core/di/app_services.dart';
import 'package:mine32_pos/core/di/providers.dart';
import 'package:mine32_pos/core/time/clock.dart';
import 'package:mine32_pos/features/accounting/data/accounting_repository.dart';
import 'package:mine32_pos/features/accounting/domain/accounting_models.dart';
import 'package:mine32_pos/features/accounting/presentation/accounting_screen.dart';

void main() {
  testWidgets('journals tab lists a posted manual journal', (tester) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final services = await AppServices.initialize(
      database: AppDatabase(NativeDatabase.memory()),
      clock: MutableClock(1000),
    );
    addTearDown(services.dispose);

    final acct = AccountingRepository(
      db: services.db,
      changeLog: services.changeLog,
      hlcService: services.hlc,
      clock: services.clock,
    );
    final cash = (await acct.accountByCode(AccountCode.cash))!;
    final equity = (await acct.accountByCode(AccountCode.ownerEquity))!;
    await acct.postManualJournal(
      date: DateTime(2026, 1, 2).millisecondsSinceEpoch,
      memo: 'Opening cash',
      lines: [
        JournalLineInput(accountId: cash.id, debitMinor: 5000),
        JournalLineInput(accountId: equity.id, creditMinor: 5000),
      ],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [appServicesProvider.overrideWithValue(services)],
        child: const MaterialApp(home: Scaffold(body: AccountingScreen())),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    // Switch to the Journals tab (let the tab animation + stream settle).
    await tester.tap(find.text('Journals'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Opening cash'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 500));
  });

  testWidgets('tax rates tab shows the seeded PPN rate', (tester) async {
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
        child: const MaterialApp(home: Scaffold(body: AccountingScreen())),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    await tester.tap(find.text('Tax rates'));
    await tester.pumpAndSettle();

    expect(find.text('PPN 11%'), findsOneWidget);
    expect(find.textContaining('11% · inclusive'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 500));
  });
}
