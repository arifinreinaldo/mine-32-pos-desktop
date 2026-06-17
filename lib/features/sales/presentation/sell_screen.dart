import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:printing/printing.dart';

import '../../../core/di/providers.dart';
import '../../../core/money/money.dart';
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

  void _park(WidgetRef ref) {
    ref
        .read(parkedSalesProvider.notifier)
        .park(
          ref.read(cartProvider),
          customerId: ref.read(sellCustomerProvider),
        );
    ref.read(cartProvider.notifier).clear();
    ref.read(sellCustomerProvider.notifier).select(null);
  }

  void _recall(BuildContext context, WidgetRef ref, int index) {
    if (ref.read(cartProvider).isNotEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Park or clear the current sale before recalling'),
        ),
      );
      return;
    }
    final sale = ref.read(parkedSalesProvider.notifier).recallAt(index);
    if (sale == null) return;
    ref.read(cartProvider.notifier).replace(sale.cart);
    ref.read(sellCustomerProvider.notifier).select(sale.customerId);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cart = ref.watch(cartProvider);
    final money = ref.watch(moneyFormatProvider);
    final parked = ref.watch(parkedSalesProvider);
    final theme = Theme.of(context);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Current sale',
                    style: theme.textTheme.titleMedium,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (parked.isNotEmpty)
                  PopupMenuButton<int>(
                    tooltip: 'Recall a parked sale',
                    onSelected: (i) => _recall(context, ref, i),
                    itemBuilder: (_) => [
                      for (var i = 0; i < parked.length; i++)
                        PopupMenuItem(value: i, child: Text(parked[i].label)),
                    ],
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: Text(
                        'Parked (${parked.length})',
                        style: theme.textTheme.labelLarge?.copyWith(
                          color: theme.colorScheme.primary,
                        ),
                      ),
                    ),
                  ),
                if (cart.isNotEmpty) ...[
                  IconButton(
                    tooltip: 'Park sale',
                    visualDensity: VisualDensity.compact,
                    icon: const Icon(Icons.pause_circle_outline, size: 20),
                    onPressed: () => _park(ref),
                  ),
                  IconButton(
                    tooltip: 'Clear',
                    visualDensity: VisualDensity.compact,
                    icon: const Icon(Icons.clear_all, size: 20),
                    onPressed: () => ref.read(cartProvider.notifier).clear(),
                  ),
                ],
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
    // Collapse the tier choice into each line's charged unit price so the posted
    // sale and receipt record what was actually billed.
    final w = cart.wholesale;
    final lines = [
      for (final l in cart.lines)
        CartLine(
          variantId: l.variantId,
          sku: l.sku,
          name: l.name,
          unitPrice: l.effectiveUnitPrice(w),
          unitCost: l.unitCost,
          qty: l.qty,
          discount: l.discount,
        ),
    ];
    final result = await PaymentDialog.show(
      context,
      lines: lines,
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
    if (selected == null) return;
    final id = selected.isEmpty ? null : selected;
    ref.read(sellCustomerProvider.notifier).select(id);
    // Switch the cart to the customer's pricing tier.
    final wholesale =
        id != null &&
        (await ref.read(customersRepositoryProvider).getCustomer(id))
                ?.priceTier ==
            'wholesale';
    ref.read(cartProvider.notifier).setWholesale(wholesale);
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
    final theme = Theme.of(context);
    final money = ref.watch(moneyFormatProvider);
    final notifier = ref.read(cartProvider.notifier);
    final wholesale = ref.watch(cartProvider).wholesale;
    final unitPrice = line.effectiveUnitPrice(wholesale);
    final lineTotal = line.effectiveTotal(wholesale);
    final hasDiscount = line.discount.minorUnits > 0;
    final isWholesalePriced =
        wholesale && line.wholesaleUnitPrice.minorUnits > 0;
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
                  '${line.sku} • ${money.format(unitPrice)}'
                  '${isWholesalePriced ? ' (wholesale)' : ''}'
                  '${hasDiscount ? ' • −${money.format(line.discount)}' : ''}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: hasDiscount ? theme.colorScheme.tertiary : null,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            tooltip: 'Discount',
            icon: Icon(
              hasDiscount ? Icons.local_offer : Icons.local_offer_outlined,
              size: 18,
              color: hasDiscount ? theme.colorScheme.tertiary : null,
            ),
            onPressed: () => _editDiscount(context, ref),
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
            child: Text(money.format(lineTotal), textAlign: TextAlign.right),
          ),
        ],
      ),
    );
  }

  Future<void> _editDiscount(BuildContext context, WidgetRef ref) async {
    final result = await showDialog<Money>(
      context: context,
      builder: (_) => _LineDiscountDialog(line: line),
    );
    if (result != null) {
      ref.read(cartProvider.notifier).setLineDiscount(line.variantId, result);
    }
  }
}

/// Enter an absolute per-line discount (clamped to the line's gross by the
/// controller). Returns the chosen [Money], or `Money(0)` to clear.
class _LineDiscountDialog extends ConsumerStatefulWidget {
  final CartLine line;
  const _LineDiscountDialog({required this.line});

  @override
  ConsumerState<_LineDiscountDialog> createState() =>
      _LineDiscountDialogState();
}

class _LineDiscountDialogState extends ConsumerState<_LineDiscountDialog> {
  late final TextEditingController _amount;
  late final int _scale;
  String? _error;

  @override
  void initState() {
    super.initState();
    _scale = ref.read(currencyScaleProvider);
    final d = widget.line.discount;
    _amount = TextEditingController(
      text: d.minorUnits == 0 ? '' : d.toMajorString(scale: _scale),
    );
  }

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  void _apply() {
    final text = _amount.text.trim();
    if (text.isEmpty) {
      Navigator.of(context).pop(const Money(0));
      return;
    }
    try {
      Navigator.of(context).pop(Money.fromMajor(text, scale: _scale));
    } on FormatException {
      setState(() => _error = 'Enter a number');
    }
  }

  @override
  Widget build(BuildContext context) {
    final money = ref.watch(moneyFormatProvider);
    return AlertDialog(
      title: Text('Discount — ${widget.line.name}'),
      content: SizedBox(
        width: 320,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Line total ${money.format(widget.line.gross)}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _amount,
              autofocus: true,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: InputDecoration(
                labelText: 'Discount amount',
                errorText: _error,
              ),
              onSubmitted: (_) => _apply(),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(const Money(0)),
          child: const Text('Remove'),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _apply, child: const Text('Apply')),
      ],
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
