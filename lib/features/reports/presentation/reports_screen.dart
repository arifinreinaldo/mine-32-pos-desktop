// Chart configuration reads more clearly with explicit fl_chart defaults.
// ignore_for_file: avoid_redundant_argument_values
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/di/providers.dart';
import '../../accounting/presentation/accounting_controller.dart';
import '../data/reports_repository.dart';
import 'reports_controller.dart';

class ReportsScreen extends ConsumerWidget {
  const ReportsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final range = ref.watch(reportRangeProvider);
    final report = ref.watch(reportDataProvider);

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Text('Reports', style: theme.textTheme.headlineSmall),
              const Spacer(),
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: 'today', label: Text('Today')),
                  ButtonSegment(value: 'week', label: Text('7 days')),
                  ButtonSegment(value: 'month', label: Text('Month')),
                ],
                selected: {
                  range.label == 'Today'
                      ? 'today'
                      : range.label == 'Last 7 days'
                      ? 'week'
                      : 'month',
                },
                onSelectionChanged: (s) {
                  final notifier = ref.read(reportRangeProvider.notifier);
                  switch (s.first) {
                    case 'today':
                      notifier.today();
                    case 'week':
                      notifier.last7();
                    default:
                      notifier.thisMonth();
                  }
                },
              ),
            ],
          ),
          const SizedBox(height: 16),
          Expanded(
            child: report.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('Failed to load: $e')),
              data: (data) => _ReportBody(data: data),
            ),
          ),
        ],
      ),
    );
  }
}

class _ReportBody extends ConsumerWidget {
  final ReportData data;
  const _ReportBody({required this.data});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final money = ref.watch(moneyFormatProvider);
    final s = data.summary;
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              _StatCard(
                title: 'Sales',
                value: '${s.count}',
                icon: Icons.receipt_long_outlined,
              ),
              _StatCard(
                title: 'Revenue',
                value: money.format(s.total),
                icon: Icons.payments_outlined,
              ),
              _StatCard(
                title: 'Tax base (DPP)',
                value: money.format(s.dpp),
                icon: Icons.account_balance_outlined,
              ),
              _StatCard(
                title: 'PPN (output tax)',
                value: money.format(s.ppn),
                icon: Icons.percent_outlined,
              ),
            ],
          ),
          const SizedBox(height: 16),
          _Panel(
            title: 'Sales trend',
            child: SizedBox(height: 220, child: _SalesChart(data: data.byDay)),
          ),
          const SizedBox(height: 16),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: _Panel(
                  title: 'Top parts',
                  child: _TopParts(parts: data.topParts),
                ),
              ),
              const SizedBox(width: 16),
              const Expanded(
                child: _Panel(title: 'Trial balance', child: _TrialBalance()),
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
  const _StatCard({
    required this.title,
    required this.value,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SizedBox(
      width: 230,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              CircleAvatar(
                backgroundColor: theme.colorScheme.primaryContainer,
                foregroundColor: theme.colorScheme.onPrimaryContainer,
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

class _SalesChart extends StatelessWidget {
  final List<DayTotal> data;
  const _SalesChart({required this.data});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (data.isEmpty) {
      return Center(
        child: Text(
          'No sales in this period',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      );
    }
    final maxMajor = data
        .map((d) => d.total.minorUnits / 100.0)
        .fold<double>(0, (a, b) => b > a ? b : a);
    return BarChart(
      BarChartData(
        alignment: BarChartAlignment.spaceAround,
        maxY: maxMajor <= 0 ? 1 : maxMajor * 1.2,
        gridData: const FlGridData(show: true, drawVerticalLine: false),
        borderData: FlBorderData(show: false),
        titlesData: FlTitlesData(
          leftTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: true, reservedSize: 44),
          ),
          rightTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          topTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              getTitlesWidget: (value, meta) {
                final i = value.toInt();
                if (i < 0 || i >= data.length) return const SizedBox.shrink();
                return Text(
                  '${data[i].day.day}',
                  style: const TextStyle(fontSize: 10),
                );
              },
            ),
          ),
        ),
        barGroups: [
          for (var i = 0; i < data.length; i++)
            BarChartGroupData(
              x: i,
              barRods: [
                BarChartRodData(
                  toY: data[i].total.minorUnits / 100.0,
                  width: 14,
                  color: theme.colorScheme.primary,
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(4),
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }
}

class _TopParts extends ConsumerWidget {
  final List<PartSales> parts;
  const _TopParts({required this.parts});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (parts.isEmpty) {
      return const Text('No sales yet');
    }
    final money = ref.watch(moneyFormatProvider);
    return Column(
      children: [
        for (final p in parts)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(
              children: [
                Expanded(
                  child: Text(p.description, overflow: TextOverflow.ellipsis),
                ),
                Text('${p.qty}×  '),
                Text(money.format(p.total)),
              ],
            ),
          ),
      ],
    );
  }
}

class _TrialBalance extends ConsumerWidget {
  const _TrialBalance();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tb = ref.watch(trialBalanceProvider);
    final money = ref.watch(moneyFormatProvider);
    return tb.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Text('Error: $e'),
      data: (rows) {
        final active = rows
            .where((r) => r.debit.minorUnits != 0 || r.credit.minorUnits != 0)
            .toList();
        if (active.isEmpty) return const Text('No postings yet');
        return Column(
          children: [
            for (final r in active)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    Expanded(child: Text(r.name)),
                    Text(
                      money.format(r.balance),
                      style: TextStyle(
                        color: r.balance.isNegative
                            ? Theme.of(context).colorScheme.error
                            : null,
                      ),
                    ),
                  ],
                ),
              ),
          ],
        );
      },
    );
  }
}
