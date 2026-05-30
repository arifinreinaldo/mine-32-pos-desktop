import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:printing/printing.dart';

import '../../../core/database/app_database.dart';
import '../../../core/di/providers.dart';
import '../../../core/money/money.dart';
import '../../../shared/widgets/section_placeholder.dart';
import '../../settings/presentation/settings_controller.dart';
import '../data/receipt_builder.dart';
import '../data/receipt_pdf.dart';
import 'sales_history_controller.dart';

class SalesHistoryScreen extends ConsumerWidget {
  const SalesHistoryScreen({super.key});

  static String dateLabel(int ms) {
    final d = DateTime.fromMillisecondsSinceEpoch(ms);
    String two(int n) => n.toString().padLeft(2, '0');
    return '${d.year}-${two(d.month)}-${two(d.day)} ${two(d.hour)}:${two(d.minute)}';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final sales = ref.watch(recentSalesProvider);

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Sales history', style: theme.textTheme.headlineSmall),
          const SizedBox(height: 16),
          Expanded(
            child: sales.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('Failed to load: $e')),
              data: (rows) {
                if (rows.isEmpty) {
                  return const SectionPlaceholder(
                    title: 'No sales yet',
                    icon: Icons.receipt_long_outlined,
                    message: 'Completed sales will appear here.',
                  );
                }
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SizedBox(width: 360, child: _SalesList(sales: rows)),
                    const VerticalDivider(width: 1),
                    const Expanded(child: _SaleDetailPanel()),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _SalesList extends ConsumerWidget {
  final List<Sale> sales;
  const _SalesList({required this.sales});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final money = ref.watch(moneyFormatProvider);
    final selected = ref.watch(selectedSaleIdProvider);

    return ListView.separated(
      itemCount: sales.length,
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (context, i) {
        final s = sales[i];
        final isOnAccount = s.paidTotalMinor < s.totalMinor;
        return ListTile(
          selected: s.id == selected,
          title: Text(
            s.number,
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          subtitle: Text(SalesHistoryScreen.dateLabel(s.createdAt)),
          trailing: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(money.format(Money(s.totalMinor))),
              if (isOnAccount)
                Text(
                  'On account',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.error,
                  ),
                ),
            ],
          ),
          onTap: () => ref.read(selectedSaleIdProvider.notifier).select(s.id),
        );
      },
    );
  }
}

class _SaleDetailPanel extends ConsumerWidget {
  const _SaleDetailPanel();

  Future<void> _print(WidgetRef ref, Sale sale, List<SaleLine> lines) async {
    final settings = await ref.read(settingsRepositoryProvider).get();
    final money = ref.read(moneyFormatProvider);
    final data = buildSaleReceiptData(
      sale: sale,
      lines: lines,
      money: money,
      companyName: settings?.name ?? 'My Auto Parts',
      address: settings?.address,
      npwp: settings?.taxNumber,
      footer: settings?.receiptFooter,
    );
    await Printing.layoutPdf(onLayout: (_) => buildReceiptPdf(data));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final money = ref.watch(moneyFormatProvider);
    final selectedId = ref.watch(selectedSaleIdProvider);
    if (selectedId == null) {
      return const SectionPlaceholder(
        title: 'Select a sale',
        icon: Icons.touch_app_outlined,
        message: 'Pick a sale on the left to see its details.',
      );
    }
    final detail = ref.watch(saleDetailProvider(selectedId));
    return detail.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Failed to load: $e')),
      data: (d) {
        if (d == null) return const Center(child: Text('Sale not found'));
        final sale = d.sale;
        final hasTax = sale.taxTotalMinor > 0;
        final change = sale.paidTotalMinor - sale.totalMinor;
        return Padding(
          padding: const EdgeInsets.only(left: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(sale.number, style: theme.textTheme.titleLarge),
                        Text(
                          SalesHistoryScreen.dateLabel(sale.createdAt),
                          style: theme.textTheme.bodySmall,
                        ),
                        if (sale.buyerName != null &&
                            sale.buyerName!.isNotEmpty)
                          Text('Buyer: ${sale.buyerName}'),
                      ],
                    ),
                  ),
                  OutlinedButton.icon(
                    onPressed: () => _print(ref, sale, d.lines),
                    icon: const Icon(Icons.print_outlined, size: 18),
                    label: const Text('Print receipt'),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              const Divider(height: 1),
              Expanded(
                child: ListView.separated(
                  itemCount: d.lines.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (context, i) {
                    final l = d.lines[i];
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Row(
                        children: [
                          SizedBox(width: 40, child: Text('${l.qty}×')),
                          Expanded(child: Text(l.description)),
                          SizedBox(
                            width: 120,
                            child: Text(
                              money.format(Money(l.unitPriceMinor)),
                              textAlign: TextAlign.right,
                            ),
                          ),
                          SizedBox(
                            width: 120,
                            child: Text(
                              money.format(Money(l.lineTotalMinor)),
                              textAlign: TextAlign.right,
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
              const Divider(),
              if (hasTax) ...[
                _totalRow(
                  context,
                  'DPP (tax base)',
                  money.format(Money(sale.subtotalMinor)),
                ),
                _totalRow(
                  context,
                  'PPN',
                  money.format(Money(sale.taxTotalMinor)),
                ),
              ],
              _totalRow(
                context,
                'Total',
                money.format(Money(sale.totalMinor)),
                emphasize: true,
              ),
              _totalRow(
                context,
                'Paid',
                money.format(Money(sale.paidTotalMinor)),
              ),
              if (change > 0)
                _totalRow(context, 'Change', money.format(Money(change))),
            ],
          ),
        );
      },
    );
  }

  Widget _totalRow(
    BuildContext context,
    String label,
    String value, {
    bool emphasize = false,
  }) {
    final theme = Theme.of(context);
    final style = emphasize
        ? theme.textTheme.titleMedium
        : theme.textTheme.bodyMedium;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          Text(label, style: style),
          const SizedBox(width: 24),
          SizedBox(
            width: 140,
            child: Text(value, textAlign: TextAlign.right, style: style),
          ),
        ],
      ),
    );
  }
}
