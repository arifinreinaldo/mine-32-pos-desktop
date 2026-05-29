import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/app_database.dart';
import '../../../core/di/providers.dart';
import '../../../core/money/money.dart';
import '../../../shared/formatters/money_format.dart';
import '../../accounting/domain/tax_math.dart';
import '../../accounting/presentation/accounting_controller.dart';
import '../../inventory/presentation/inventory_controller.dart';
import '../domain/cart.dart';
import 'sell_controller.dart';

/// Take payment for the cart and complete the sale. Returns the [SaleResult].
class PaymentDialog extends ConsumerStatefulWidget {
  final List<CartLine> lines;
  final Money total;
  const PaymentDialog({super.key, required this.lines, required this.total});

  static Future<SaleResult?> show(
    BuildContext context, {
    required List<CartLine> lines,
    required Money total,
  }) {
    return showDialog<SaleResult>(
      context: context,
      builder: (_) => PaymentDialog(lines: lines, total: total),
    );
  }

  @override
  ConsumerState<PaymentDialog> createState() => _PaymentDialogState();
}

class _PaymentDialogState extends ConsumerState<PaymentDialog> {
  late final TextEditingController _tendered;
  late final int _scale;
  String _method = 'cash';
  bool _saving = false;
  TaxRate? _taxRate;

  @override
  void initState() {
    super.initState();
    _scale = ref.read(currencyScaleProvider);
    _tendered = TextEditingController(
      text: widget.total.toMajorString(scale: _scale),
    );
    _loadTaxRate();
  }

  Future<void> _loadTaxRate() async {
    final rate = await ref.read(accountingRepositoryProvider).defaultTaxRate();
    if (mounted) setState(() => _taxRate = rate);
  }

  @override
  void dispose() {
    _tendered.dispose();
    super.dispose();
  }

  Money get _tenderedMoney {
    if (_method != 'cash') return widget.total;
    final t = _tendered.text.trim();
    if (t.isEmpty) return const Money(0);
    // Desktop number fields still accept stray characters; never throw in build.
    try {
      return Money.fromMajor(t, scale: _scale);
    } on FormatException {
      return const Money(0);
    }
  }

  Money get _change {
    final c = _tenderedMoney - widget.total;
    return c.isNegative ? const Money(0) : c;
  }

  bool get _canComplete => _method != 'cash' || _tenderedMoney >= widget.total;

  Future<void> _complete() async {
    setState(() => _saving = true);
    final locationId = await ref
        .read(inventoryRepositoryProvider)
        .ensureDefaultLocation();
    final rate = _taxRate;
    final result = await ref
        .read(salesRepositoryProvider)
        .completeSale(
          lines: widget.lines,
          locationId: locationId,
          tendered: _tenderedMoney,
          method: _method,
          taxBasisPoints: rate?.basisPoints ?? 0,
          taxInclusive: rate?.inclusive ?? true,
        );
    if (mounted) Navigator.of(context).pop(result);
  }

  /// DPP (tax base) + PPN breakdown of the inclusive total.
  Widget _taxBreakdown(MoneyFormat money, ThemeData theme) {
    final rate = _taxRate!;
    final amounts = TaxMath.split(
      amountMinor: widget.total.minorUnits,
      basisPoints: rate.basisPoints,
      inclusive: rate.inclusive,
    );
    final style = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    Widget line(String label, int value) => Padding(
      padding: const EdgeInsets.only(top: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: style),
          Text(money.format(Money(value)), style: style),
        ],
      ),
    );
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Column(
        children: [
          line('Tax base (DPP)', amounts.baseMinor),
          line('${rate.name} (included)', amounts.taxMinor),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final money = ref.watch(moneyFormatProvider);
    final theme = Theme.of(context);
    return AlertDialog(
      title: const Text('Take payment'),
      content: SizedBox(
        width: 360,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Total', style: theme.textTheme.titleMedium),
                Text(
                  money.format(widget.total),
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            if (_taxRate != null && _taxRate!.basisPoints > 0)
              _taxBreakdown(money, theme),
            const SizedBox(height: 16),
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'cash', label: Text('Cash')),
                ButtonSegment(value: 'card', label: Text('Card')),
                ButtonSegment(value: 'transfer', label: Text('Transfer')),
              ],
              selected: {_method},
              onSelectionChanged: (s) => setState(() => _method = s.first),
            ),
            if (_method == 'cash') ...[
              const SizedBox(height: 16),
              TextField(
                controller: _tendered,
                autofocus: true,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Cash tendered'),
                onChanged: (_) => setState(() {}),
                onSubmitted: (_) {
                  if (_canComplete && !_saving) _complete();
                },
              ),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Change', style: theme.textTheme.titleMedium),
                  Text(
                    money.format(_change),
                    style: theme.textTheme.titleMedium,
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: (_canComplete && !_saving) ? _complete : null,
          child: Text(_saving ? 'Completing…' : 'Complete sale'),
        ),
      ],
    );
  }
}
