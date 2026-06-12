import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:window_manager/window_manager.dart';

import 'app/app.dart';
import 'core/di/app_services.dart';
import 'core/di/providers.dart';
import 'core/errors/app_error_reporter.dart';
import 'features/sync/data/sync_scheduler.dart';
import 'features/sync/data/sync_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Route uncaught framework/platform errors to a user-facing snackbar.
  final errorReporter = AppErrorReporter()..install();

  if (_isDesktop) {
    await windowManager.ensureInitialized();
    const options = WindowOptions(
      size: Size(1280, 800),
      minimumSize: Size(1024, 680),
      center: true,
      title: 'Mine32 POS',
      titleBarStyle: TitleBarStyle.normal,
    );
    await windowManager.waitUntilReadyToShow(options, () async {
      await windowManager.show();
      await windowManager.focus();
    });
  }

  final services = await AppServices.initialize();

  // Background sync: every 5 minutes (and once at launch) export/import via
  // the shared folder, when one is configured on the Sync screen.
  final syncService = SyncService(services);
  SyncScheduler(
    shouldRun: () async => ((await syncService.folderPath()) ?? '').isNotEmpty,
    run: syncService.syncNow,
  ).start();

  runApp(
    ProviderScope(
      overrides: [
        appServicesProvider.overrideWithValue(services),
        errorReporterProvider.overrideWithValue(errorReporter),
      ],
      child: const MineApp(),
    ),
  );
}

bool get _isDesktop =>
    Platform.isWindows || Platform.isLinux || Platform.isMacOS;
