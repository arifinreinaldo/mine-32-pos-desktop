import 'package:go_router/go_router.dart';

import '../features/accounting/presentation/accounting_screen.dart';
import '../features/catalog/presentation/catalog_screen.dart';
import '../features/customers/presentation/customers_screen.dart';
import '../features/dashboard/presentation/dashboard_screen.dart';
import '../features/inventory/presentation/inventory_screen.dart';
import '../features/purchasing/presentation/purchasing_screen.dart';
import '../features/reports/presentation/reports_screen.dart';
import '../features/sales/presentation/sales_history_screen.dart';
import '../features/sales/presentation/sell_screen.dart';
import '../features/settings/presentation/settings_screen.dart';
import '../features/sync/presentation/sync_screen.dart';
import '../shared/widgets/app_shell.dart';

/// App routing: one shell (side nav) wrapping the section routes.
final appRouter = GoRouter(
  initialLocation: '/dashboard',
  routes: [
    ShellRoute(
      builder: (context, state, child) => AppShell(child: child),
      routes: [
        GoRoute(
          path: '/dashboard',
          builder: (context, state) => const DashboardScreen(),
        ),
        GoRoute(path: '/sell', builder: (context, state) => const SellScreen()),
        GoRoute(
          path: '/sales',
          builder: (context, state) => const SalesHistoryScreen(),
        ),
        GoRoute(
          path: '/catalog',
          builder: (context, state) => const CatalogScreen(),
        ),
        GoRoute(
          path: '/inventory',
          builder: (context, state) => const InventoryScreen(),
        ),
        GoRoute(
          path: '/purchasing',
          builder: (context, state) => const PurchasingScreen(),
        ),
        GoRoute(
          path: '/customers',
          builder: (context, state) => const CustomersScreen(),
        ),
        GoRoute(
          path: '/accounting',
          builder: (context, state) => const AccountingScreen(),
        ),
        GoRoute(
          path: '/reports',
          builder: (context, state) => const ReportsScreen(),
        ),
        GoRoute(path: '/sync', builder: (context, state) => const SyncScreen()),
        GoRoute(
          path: '/settings',
          builder: (context, state) => const SettingsScreen(),
        ),
      ],
    ),
  ],
);
