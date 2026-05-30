import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/di/providers.dart';
import '../../../core/money/money.dart';
import '../../../shared/formatters/money_format.dart';
import '../data/returns_repository.dart';
import 'returns_controller.dart';
import 'sales_history_controller.dart';

/// Return / refund flow for a completed sale: choose a quantity per line (up to
/// the remaining returnable amount), pick the refund method, and post. Returns
/// `true` when a return was created.
class ReturnDialog extends ConsumerStatefulWidget {
  final String saleId;
  final String saleNumber;
  const ReturnDialog({
    super.key,
    required this.saleId,
    required this.saleNumber,
  });

  static Future<bool?> show(
    BuildContext context, {
    required String saleId,
    required String saleNumber,
  }) {
    return showDialog<bool>(
      context: context,
      builder: (_) => ReturnDialog(saleId: saleId, saleNumber: saleNumber),
    );
  }

  @override
  ConsumerState<ReturnDialog> createState() => _ReturnDialogState();
}

class _ReturnDialogState extends ConsumerState<ReturnDialog> {
  final _qty = <String, int>{}; // saleLineId -> qty to return
  final _reason = TextEditingController();
  String _method = 'cash';
  bool _posting = false;
  bool _seeded = false;

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  Future<void> _post() async {
    final picks = {
      for (final e in _qty.entries)
        if (e.value > 0) e.key: e.value,
    };
    if (picks.isEmpty) return;
    setState(() => _posting = true);
    try {
      final result = await ref
          .read(returnsRepositoryProvider)
          .createReturn(
            saleId: widget.saleId,
            quantitiesBySaleLineId: picks,
            refundMethod: _method,
            reason: _reason.text.trim().isEmpty ? null : _reason.text.trim(),
          );
      // Refresh the sale detail (paid/returnable) behind the dialog.
      ref.invalidate(saleDetailProvider(widget.saleId));
      ref.invalidate(returnableLinesProvider(widget.saleId));
      if (mounted) {
        Navigator.of(context).pop(true);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Refunded ${result.number} · ${ref.read(moneyFormatProvider).format(result.total)}',
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _posting = false);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Could not refund: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final money = ref.watch(moneyFormatProvider);
    final linesAsync = ref.watch(returnableLinesProvider(widget.saleId));

    return AlertDialog(
      title: Text('Return ${widget.saleNumber}'),
      content: SizedBox(
        width: 560,
        child: linesAsync.when(
          loading: () => const SizedBox(
            height: 80,
            child: Center(child: CircularProgressIndicator()),
          ),
          error: (e, _) => Text('Failed to load: $e'),
          data: (lines) {
            if (lines.isEmpty) {
              return const Padding(
                padding: EdgeInsets.all(8),
                child: Text('Nothing left to return on this sale.'),
              );
            }
            if (!_seeded) {
              for (final l in lines) {
                _qty[l.line.id] = l.remaining; // default: full remaining
              }
              _seeded = true;
            }
            var refundTotal = 0;
            for (final l in lines) {
              final q = _qty[l.line.id] ?? 0;
              if (q > 0) {
                refundTotal += ((l.line.lineTotalMinor * q) / l.line.qty)
                    .round();
              }
            }
            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 280),
                  child: SingleChildScrollView(
                    child: Column(
                      children: [for (final l in lines) _lineRow(l, money)],
                    ),
                  ),
                ),
                const Divider(),
                Row(
                  children: [
                    const Text('Refund to'),
                    const SizedBox(width: 12),
                    DropdownButton<String>(
                      value: _method,
                      items: const [
                        DropdownMenuItem(value: 'cash', child: Text('Cash')),
                        DropdownMenuItem(value: 'bank', child: Text('Bank')),
                      ],
                      onChanged: (v) => setState(() => _method = v ?? 'cash'),
                    ),
                    const Spacer(),
                    Text(
                      'Refund ${money.format(Money(refundTotal))}',
                      style: theme.textTheme.titleMedium,
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _reason,
                  decoration: const InputDecoration(
                    labelText: 'Reason (optional)',
                    isDense: true,
                  ),
                ),
              ],
            );
          },
        ),
      ),
      actions: [
        TextButton(
          onPressed: _posting ? null : () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _posting ? null : _post,
          child: Text(_posting ? 'Refunding…' : 'Refund'),
        ),
      ],
    );
  }

  Widget _lineRow(ReturnableLine l, MoneyFormat money) {
    final current = _qty[l.line.id] ?? 0;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(child: Text(l.line.description)),
          Text('${money.format(Money(l.line.unitPriceMinor))}  '),
          IconButton(
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.remove_circle_outline, size: 20),
            onPressed: current > 0
                ? () => setState(() => _qty[l.line.id] = current - 1)
                : null,
          ),
          SizedBox(
            width: 56,
            child: Text(
              '$current / ${l.remaining}',
              textAlign: TextAlign.center,
            ),
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.add_circle_outline, size: 20),
            onPressed: current < l.remaining
                ? () => setState(() => _qty[l.line.id] = current + 1)
                : null,
          ),
        ],
      ),
    );
  }
}
