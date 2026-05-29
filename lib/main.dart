import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:window_manager/window_manager.dart';

import 'app/app.dart';
import 'core/di/app_services.dart';
import 'core/di/providers.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

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

  runApp(
    ProviderScope(
      overrides: [appServicesProvider.overrideWithValue(services)],
      child: const MineApp(),
    ),
  );
}

bool get _isDesktop =>
    Platform.isWindows || Platform.isLinux || Platform.isMacOS;
