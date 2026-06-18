// Chart configuration reads more clearly with explicit fl_chart defaults.
// ignore_for_file: avoid_redundant_argument_values
import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/di/providers.dart';
import '../../accounting/domain/coretax_csv.dart';
import '../../accounting/domain/coretax_xml.dart';
import '../../accounting/presentation/accounting_controller.dart';
import '../../settings/presentation/settings_controller.dart';
import '../data/reports_repository.dart';
import 'reports_controller.dart';

class ReportsScreen extends ConsumerWidget {
  const ReportsScreen({super.key});

  Future<void> _exportPpnCsv(BuildContext context, WidgetRef ref) async {
    final range = ref.read(reportRangeProvider);
    final rows = await ref
        .read(accountingRepositoryProvider)
        .fakturRowsForPeriod(fromMs: range.fromMs, toMs: range.toMs);
    final scale = ref.read(moneyFormatProvider).scale;
    final csv = buildCoreTaxCsv(rows, scale: scale);
    final path = await FilePicker.saveFile(
      dialogTitle: 'Export PPN CSV',
      fileName: 'ppn-${range.label.toLowerCase().replaceAll(' ', '-')}.csv',
      bytes: Uint8List.fromList(utf8.encode(csv)),
    );
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            path == null
                ? 'Export cancelled'
                : 'Exported ${rows.length} faktur row(s)',
          ),
        ),
      );
    }
  }

  Future<void> _exportPpnXml(BuildContext context, WidgetRef ref) async {
    final range = ref.read(reportRangeProvider);
    final settings = await ref.read(settingsRepositoryProvider).get();
    final invoices = await ref
        .read(accountingRepositoryProvider)
        .fakturXmlInvoicesForPeriod(fromMs: range.fromMs, toMs: range.toMs);
    final scale = ref.read(moneyFormatProvider).scale;
    final xml = buildCoreTaxXml(
      sellerTin: settings?.taxNumber ?? '',
      invoices: invoices,
      scale: scale,
    );
    final path = await FilePicker.saveFile(
      dialogTitle: 'Export CoreTax XML',
      fileName: 'coretax-${range.label.toLowerCase().replaceAll(' ', '-')}.xml',
      bytes: Uint8List.fromList(utf8.encode(xml)),
    );
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            path == null
                ? 'Export cancelled'
                : 'Exported ${invoices.length} tax invoice(s)',
          ),
        ),
      );
    }
  }

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
              OutlinedButton.icon(
                onPressed: () => _exportPpnCsv(context, ref),
                icon: const Icon(Icons.download_outlined),
                label: const Text('PPN CSV'),
              ),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                onPressed: () => _exportPpnXml(context, ref),
                icon: const Icon(Icons.code_outlined),
                label: const Text('CoreTax XML'),
              ),
              const SizedBox(width: 12),
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
          const SizedBox(height: 16),
          const Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: _Panel(title: 'Profit & Loss', child: _PlBody()),
              ),
              SizedBox(width: 16),
              Expanded(
                child: _Panel(
                  title: 'Balance sheet',
                  child: _BalanceSheetBody(),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          const _Panel(title: 'PPN (VAT)', child: _PpnBody()),
        ],
      ),
    );
  }
}

class _PpnBody extends ConsumerWidget {
  const _PpnBody();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ppn = ref.watch(netPpnProvider);
    final money = ref.watch(moneyFormatProvider);
    final theme = Theme.of(context);
    return ppn.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Text('Error: $e'),
      data: (r) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _kv('Output PPN (sales)', money.format(r.output)),
          _kv('Input PPN (purchases)', money.format(r.input)),
          const Divider(),
          _kv(
            r.payable.isNegative ? 'PPN refundable' : 'PPN payable',
            money.format(r.payable.abs()),
            bold: true,
          ),
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              'Output − input. File via Reports → CoreTax XML / PPN CSV.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PlBody extends ConsumerWidget {
  const _PlBody();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pl = ref.watch(plReportProvider);
    final money = ref.watch(moneyFormatProvider);
    final theme = Theme.of(context);
    return pl.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Text('Error: $e'),
      data: (r) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final l in r.income) _kv(l.name, money.format(l.amount)),
          _kv('Total income', money.format(r.totalIncome), bold: true),
          const SizedBox(height: 8),
          for (final l in r.expense) _kv(l.name, money.format(l.amount)),
          _kv('Total expenses', money.format(r.totalExpense), bold: true),
          const Divider(),
          _kv(
            'Net profit',
            money.format(r.netProfit),
            bold: true,
            color: r.netProfit.isNegative ? theme.colorScheme.error : null,
          ),
        ],
      ),
    );
  }
}

class _BalanceSheetBody extends ConsumerWidget {
  const _BalanceSheetBody();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bs = ref.watch(balanceSheetProvider);
    final money = ref.watch(moneyFormatProvider);
    final theme = Theme.of(context);
    return bs.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Text('Error: $e'),
      data: (r) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Assets', style: theme.textTheme.labelLarge),
          for (final l in r.assets) _kv(l.name, money.format(l.amount)),
          _kv('Total assets', money.format(r.totalAssets), bold: true),
          const SizedBox(height: 8),
          Text('Liabilities', style: theme.textTheme.labelLarge),
          for (final l in r.liabilities) _kv(l.name, money.format(l.amount)),
          _kv(
            'Total liabilities',
            money.format(r.totalLiabilities),
            bold: true,
          ),
          const SizedBox(height: 8),
          Text('Equity', style: theme.textTheme.labelLarge),
          for (final l in r.equity) _kv(l.name, money.format(l.amount)),
          _kv('Total equity', money.format(r.totalEquity), bold: true),
          const Divider(),
          Row(
            children: [
              Icon(
                r.balanced ? Icons.check_circle_outline : Icons.error_outline,
                size: 16,
                color: r.balanced ? Colors.green : theme.colorScheme.error,
              ),
              const SizedBox(width: 6),
              Text(r.balanced ? 'Balanced' : 'Out of balance'),
            ],
          ),
        ],
      ),
    );
  }
}

Widget _kv(String k, String v, {bool bold = false, Color? color}) {
  return Builder(
    builder: (context) {
      final style = Theme.of(context).textTheme.bodyMedium?.copyWith(
        fontWeight: bold ? FontWeight.bold : null,
        color: color,
      );
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Flexible(child: Text(k, style: style)),
            Text(v, style: style),
          ],
        ),
      );
    },
  );
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
