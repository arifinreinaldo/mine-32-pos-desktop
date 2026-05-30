import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:printing/printing.dart';

import '../../../core/di/providers.dart';
import '../../customers/presentation/customers_controller.dart';
import '../../settings/presentation/settings_controller.dart';
import '../data/receipt_builder.dart';
import '../data/receipt_pdf.dart';
import '../domain/cart.dart';
import 'payment_dialog.dart';
import 'sell_controller.dart';

class SellScreen extends ConsumerWidget {
  const SellScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return const Padding(
      padding: EdgeInsets.all(16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(flex: 5, child: _SearchPanel()),
          SizedBox(width: 16),
          SizedBox(width: 380, child: _CartPanel()),
        ],
      ),
    );
  }
}

class _SearchPanel extends ConsumerStatefulWidget {
  const _SearchPanel();

  @override
  ConsumerState<_SearchPanel> createState() => _SearchPanelState();
}

class _SearchPanelState extends ConsumerState<_SearchPanel> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _addFirstAndClear() {
    final results = ref.read(sellResultsProvider).value ?? const [];
    if (results.isNotEmpty) {
      ref.read(cartProvider.notifier).addItem(results.first);
      _controller.clear();
      ref.read(sellSearchProvider.notifier).update('');
    }
  }

  @override
  Widget build(BuildContext context) {
    final results = ref.watch(sellResultsProvider);
    final money = ref.watch(moneyFormatProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: _controller,
          autofocus: true,
          decoration: const InputDecoration(
            prefixIcon: Icon(Icons.search),
            hintText: 'Search or scan a part (SKU, name, barcode)',
          ),
          onChanged: (v) => ref.read(sellSearchProvider.notifier).update(v),
          onSubmitted: (_) => _addFirstAndClear(),
        ),
        const SizedBox(height: 12),
        Expanded(
          child: results.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Center(child: Text('Error: $e')),
            data: (items) {
              if (items.isEmpty) {
                return Center(
                  child: Text(
                    'Search to add parts to the sale',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                );
              }
              return ListView.separated(
                itemCount: items.length,
                separatorBuilder: (_, _) => const Divider(height: 1),
                itemBuilder: (context, i) {
                  final item = items[i];
                  return ListTile(
                    title: Text(item.productName),
                    subtitle: Text(
                      '${item.sku}${item.brandName != null ? ' • ${item.brandName}' : ''}',
                    ),
                    trailing: Text(money.format(item.price)),
                    onTap: () => ref.read(cartProvider.notifier).addItem(item),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }
}

class _CartPanel extends ConsumerWidget {
  const _CartPanel();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cart = ref.watch(cartProvider);
    final money = ref.watch(moneyFormatProvider);
    final theme = Theme.of(context);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Text('Current sale', style: theme.textTheme.titleMedium),
                const Spacer(),
                if (cart.isNotEmpty)
                  TextButton.icon(
                    onPressed: () => ref.read(cartProvider.notifier).clear(),
                    icon: const Icon(Icons.clear_all, size: 18),
                    label: const Text('Clear'),
                  ),
              ],
            ),
            _CustomerSelector(onPick: () => _pickCustomer(context, ref)),
            const Divider(),
            Expanded(
              child: cart.isEmpty
                  ? Center(
                      child: Text(
                        'No items yet',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    )
                  : ListView.separated(
                      itemCount: cart.lines.length,
                      separatorBuilder: (_, _) => const Divider(height: 1),
                      itemBuilder: (context, i) =>
                          _CartLineRow(line: cart.lines[i]),
                    ),
            ),
            const Divider(),
            _TotalRow(label: 'Subtotal', value: money.format(cart.subtotal)),
            const SizedBox(height: 4),
            _TotalRow(
              label: 'Total',
              value: money.format(cart.total),
              emphasize: true,
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: cart.isEmpty
                  ? null
                  : () => _charge(context, ref, cart),
              icon: const Icon(Icons.payments_outlined),
              label: Text('Charge ${money.format(cart.total)}'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _charge(BuildContext context, WidgetRef ref, Cart cart) async {
    final result = await PaymentDialog.show(
      context,
      lines: cart.lines,
      total: cart.total,
      customerId: ref.read(sellCustomerProvider),
    );
    if (result == null || !context.mounted) return;
    ref.read(cartProvider.notifier).clear();
    final money = ref.read(moneyFormatProvider);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Sale ${result.number} completed • change ${money.format(result.change)}',
        ),
        action: SnackBarAction(
          label: 'Print',
          onPressed: () => _printReceipt(ref, result.saleId),
        ),
      ),
    );
  }

  Future<void> _printReceipt(WidgetRef ref, String saleId) async {
    final salesRepo = ref.read(salesRepositoryProvider);
    final sale = await salesRepo.getSale(saleId);
    if (sale == null) return;
    final lines = await salesRepo.linesForSale(saleId);
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

  Future<void> _pickCustomer(BuildContext context, WidgetRef ref) async {
    final selected = await showDialog<String?>(
      context: context,
      builder: (_) => const _CustomerPickerDialog(),
    );
    // A sentinel '' means "Walk-in (clear)".
    if (selected != null) {
      ref
          .read(sellCustomerProvider.notifier)
          .select(selected.isEmpty ? null : selected);
    }
  }
}

class _CustomerSelector extends ConsumerWidget {
  final VoidCallback onPick;
  const _CustomerSelector({required this.onPick});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final id = ref.watch(sellCustomerProvider);
    final customers = ref.watch(customersProvider).value ?? const [];
    final name = id == null
        ? 'Walk-in customer'
        : customers.where((c) => c.id == id).map((c) => c.name).firstOrNull ??
              'Customer';
    return InkWell(
      onTap: onPick,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          children: [
            const Icon(Icons.person_outline, size: 18),
            const SizedBox(width: 8),
            Expanded(child: Text(name, overflow: TextOverflow.ellipsis)),
            const Icon(Icons.arrow_drop_down),
          ],
        ),
      ),
    );
  }
}

class _CustomerPickerDialog extends ConsumerWidget {
  const _CustomerPickerDialog();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final customers = ref.watch(customersProvider);
    return AlertDialog(
      title: const Text('Choose customer'),
      content: SizedBox(
        width: 360,
        height: 380,
        child: customers.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(child: Text('Error: $e')),
          data: (list) => ListView(
            children: [
              ListTile(
                leading: const Icon(Icons.person_off_outlined),
                title: const Text('Walk-in (no customer)'),
                onTap: () => Navigator.of(context).pop(''),
              ),
              const Divider(height: 1),
              for (final c in list)
                ListTile(
                  leading: const Icon(Icons.person_outline),
                  title: Text(c.name),
                  subtitle: Text(c.phone ?? c.email ?? '—'),
                  onTap: () => Navigator.of(context).pop(c.id),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CartLineRow extends ConsumerWidget {
  final CartLine line;
  const _CartLineRow({required this.line});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final money = ref.watch(moneyFormatProvider);
    final notifier = ref.read(cartProvider.notifier);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(line.name, overflow: TextOverflow.ellipsis),
                Text(
                  '${line.sku} • ${money.format(line.unitPrice)}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.remove_circle_outline, size: 20),
            onPressed: () => notifier.setQty(line.variantId, line.qty - 1),
          ),
          Text('${line.qty}'),
          IconButton(
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.add_circle_outline, size: 20),
            onPressed: () => notifier.setQty(line.variantId, line.qty + 1),
          ),
          SizedBox(
            width: 72,
            child: Text(money.format(line.total), textAlign: TextAlign.right),
          ),
        ],
      ),
    );
  }
}

class _TotalRow extends StatelessWidget {
  final String label;
  final String value;
  final bool emphasize;
  const _TotalRow({
    required this.label,
    required this.value,
    this.emphasize = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final style = emphasize
        ? theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)
        : theme.textTheme.bodyMedium;
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: style),
        Text(value, style: style),
      ],
    );
  }
}
