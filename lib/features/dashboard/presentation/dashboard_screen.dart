import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/di/providers.dart';
import '../../../core/money/money.dart';
import '../../inventory/presentation/inventory_controller.dart';
import 'dashboard_controller.dart';

class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final money = ref.watch(moneyFormatProvider);
    final today = ref.watch(todayReportProvider);
    final stock = ref.watch(stockLevelsProvider);
    final recent = ref.watch(recentSalesProvider);

    final lowStock = stock.value?.where((s) => s.isLow).toList() ?? const [];
    final partCount = stock.value?.length ?? 0;
    final todaySummary = today.value?.summary;

    return Padding(
      padding: const EdgeInsets.all(16),
      child: ListView(
        children: [
          Text('Dashboard', style: theme.textTheme.headlineSmall),
          const SizedBox(height: 16),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              _StatCard(
                title: "Today's sales",
                value: '${todaySummary?.count ?? 0}',
                icon: Icons.receipt_long_outlined,
              ),
              _StatCard(
                title: "Today's revenue",
                value: money.format(todaySummary?.total ?? const Money(0)),
                icon: Icons.payments_outlined,
              ),
              _StatCard(
                title: 'Low stock',
                value: '${lowStock.length}',
                icon: Icons.warning_amber_outlined,
                highlight: lowStock.isNotEmpty,
              ),
              _StatCard(
                title: 'Parts',
                value: '$partCount',
                icon: Icons.inventory_2_outlined,
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: _Panel(
                  title: 'Recent sales',
                  child: recent.when(
                    loading: () =>
                        const Center(child: CircularProgressIndicator()),
                    error: (e, _) => Text('Error: $e'),
                    data: (sales) => sales.isEmpty
                        ? const Text('No sales yet')
                        : Column(
                            children: [
                              for (final s in sales)
                                Padding(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 6,
                                  ),
                                  child: Row(
                                    children: [
                                      Expanded(child: Text(s.number)),
                                      Text(money.format(Money(s.totalMinor))),
                                    ],
                                  ),
                                ),
                            ],
                          ),
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: _Panel(
                  title: 'Low stock',
                  child: lowStock.isEmpty
                      ? const Text('Everything in stock')
                      : Column(
                          children: [
                            for (final s in lowStock.take(8))
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 6,
                                ),
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        '${s.sku} · ${s.productName}',
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                    Text(
                                      '${s.onHand}',
                                      style: TextStyle(
                                        color: theme.colorScheme.error,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                          ],
                        ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  final String title;
  final String value;
  final IconData icon;
  final bool highlight;
  const _StatCard({
    required this.title,
    required this.value,
    required this.icon,
    this.highlight = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bg = highlight
        ? theme.colorScheme.errorContainer
        : theme.colorScheme.primaryContainer;
    final fg = highlight
        ? theme.colorScheme.onErrorContainer
        : theme.colorScheme.onPrimaryContainer;
    return SizedBox(
      width: 230,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              CircleAvatar(
                backgroundColor: bg,
                foregroundColor: fg,
                child: Icon(icon, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: theme.textTheme.labelMedium),
                    const SizedBox(height: 2),
                    Text(
                      value,
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Panel extends StatelessWidget {
  final String title;
  final Widget child;
  const _Panel({required this.title, required this.child});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              title,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 12),
            child,
          ],
        ),
      ),
    );
  }
}
