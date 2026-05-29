import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/di/providers.dart';
import '../../../core/money/money.dart';
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
  String _method = 'cash';
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _tendered = TextEditingController(text: widget.total.toMajorString());
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
    return Money.fromMajor(t);
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
    final result = await ref
        .read(salesRepositoryProvider)
        .completeSale(
          lines: widget.lines,
          locationId: locationId,
          tendered: _tenderedMoney,
          method: _method,
        );
    if (mounted) Navigator.of(context).pop(result);
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
