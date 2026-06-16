import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/app_database.dart';
import 'purchasing_controller.dart';

/// Receive a purchase order, fully or partially: each line shows its
/// outstanding quantity with an editable "receive now" field (defaulting to the
/// full remainder). Returns `true` when something was received.
class ReceivePoDialog extends ConsumerStatefulWidget {
  final String poId;
  final String poNumber;
  const ReceivePoDialog({
    super.key,
    required this.poId,
    required this.poNumber,
  });

  static Future<bool?> show(
    BuildContext context, {
    required String poId,
    required String poNumber,
  }) {
    return showDialog<bool>(
      context: context,
      builder: (_) => ReceivePoDialog(poId: poId, poNumber: poNumber),
    );
  }

  @override
  ConsumerState<ReceivePoDialog> createState() => _ReceivePoDialogState();
}

class _LineRow {
  final PurchaseOrderLine line;
  final int remaining;
  final TextEditingController qty;
  _LineRow(this.line, this.remaining)
    : qty = TextEditingController(text: '$remaining');
}

class _ReceivePoDialogState extends ConsumerState<ReceivePoDialog> {
  List<_LineRow> _rows = const [];
  bool _loading = true;
  bool _posting = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final lines = await ref
        .read(purchasingRepositoryProvider)
        .linesForPo(widget.poId);
    if (!mounted) return;
    setState(() {
      _rows = [
        for (final l in lines)
          if (l.qtyOrdered - l.qtyReceived > 0)
            _LineRow(l, l.qtyOrdered - l.qtyReceived),
      ];
      _loading = false;
    });
  }

  @override
  void dispose() {
    for (final r in _rows) {
      r.qty.dispose();
    }
    super.dispose();
  }

  Future<void> _post() async {
    final quantities = <String, int>{
      for (final r in _rows) r.line.id: int.tryParse(r.qty.text.trim()) ?? 0,
    };
    setState(() => _posting = true);
    await ref
        .read(purchasingRepositoryProvider)
        .receiveLines(widget.poId, quantities);
    if (mounted) Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      title: Text('Receive ${widget.poNumber}'),
      content: SizedBox(
        width: 480,
        child: _loading
            ? const SizedBox(
                height: 80,
                child: Center(child: CircularProgressIndicator()),
              )
            : _rows.isEmpty
            ? const Text('Nothing left to receive on this PO.')
            : Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      const Expanded(flex: 5, child: Text('Item')),
                      Expanded(
                        flex: 2,
                        child: Text(
                          'Remaining',
                          textAlign: TextAlign.right,
                          style: theme.textTheme.labelMedium,
                        ),
                      ),
                      const SizedBox(width: 12),
                      SizedBox(
                        width: 90,
                        child: Text(
                          'Receive',
                          style: theme.textTheme.labelMedium,
                        ),
                      ),
                    ],
                  ),
                  const Divider(),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 300),
                    child: ListView.separated(
                      shrinkWrap: true,
                      itemCount: _rows.length,
                      separatorBuilder: (_, _) => const Divider(height: 1),
                      itemBuilder: (context, i) {
                        final r = _rows[i];
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          child: Row(
                            children: [
                              Expanded(
                                flex: 5,
                                child: Text(
                                  r.line.description,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              Expanded(
                                flex: 2,
                                child: Text(
                                  '${r.remaining}',
                                  textAlign: TextAlign.right,
                                ),
                              ),
                              const SizedBox(width: 12),
                              SizedBox(
                                width: 90,
                                child: TextField(
                                  controller: r.qty,
                                  keyboardType: TextInputType.number,
                                  textAlign: TextAlign.right,
                                  decoration: const InputDecoration(
                                    isDense: true,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
      ),
      actions: [
        TextButton(
          onPressed: _posting ? null : () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: (_posting || _loading || _rows.isEmpty) ? null : _post,
          child: Text(_posting ? 'Receiving…' : 'Receive'),
        ),
      ],
    );
  }
}
