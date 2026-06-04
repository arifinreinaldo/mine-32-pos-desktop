import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/di/providers.dart';
import 'router.dart';
import 'theme/app_theme.dart';

/// Root widget. Expects `appServicesProvider` to be overridden by `main()`.
class MineApp extends ConsumerWidget {
  const MineApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp.router(
      title: 'Mine32 POS',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      routerConfig: appRouter,
      builder: (context, child) =>
          _ErrorListener(child: child ?? const SizedBox.shrink()),
    );
  }
}

/// Surfaces uncaught errors (forwarded via [errorReporterProvider]) as a
/// snackbar over whatever screen is showing.
class _ErrorListener extends ConsumerWidget {
  final Widget child;
  const _ErrorListener({required this.child});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.listen<AsyncValue<String>>(errorMessagesProvider, (_, next) {
      final message = next.asData?.value;
      if (message == null) return;
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
      );
    });
    return child;
  }
}
