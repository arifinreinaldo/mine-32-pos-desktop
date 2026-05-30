import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/di/providers.dart';
import '../../core/money/money.dart';

/// Collects a money amount + payment method (used to settle AR/AP). Returns a
/// record on save, or null on cancel. Parses at the company currency scale.
class AmountDialog extends ConsumerStatefulWidget {
  final String title;
  final int? suggested;
  const AmountDialog({super.key, required this.title, this.suggested});

  static Future<({int amountMinor, String method})?> show(
    BuildContext context, {
    required String title,
    int? suggested,
  }) {
    return showDialog<({int amountMinor, String method})>(
      context: context,
      builder: (_) => AmountDialog(title: title, suggested: suggested),
    );
  }

  @override
  ConsumerState<AmountDialog> createState() => _AmountDialogState();
}

class _AmountDialogState extends ConsumerState<AmountDialog> {
  late final TextEditingController _amount;
  late final int _scale;
  String _method = 'cash';

  @override
  void initState() {
    super.initState();
    _scale = ref.read(currencyScaleProvider);
    _amount = TextEditingController(
      text: widget.suggested != null
          ? Money(widget.suggested!).toMajorString(scale: _scale)
          : '',
    );
  }

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  int get _amountMinor {
    final t = _amount.text.trim();
    if (t.isEmpty) return 0;
    try {
      return Money.fromMajor(t, scale: _scale).minorUnits;
    } on FormatException {
      return 0;
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: SizedBox(
        width: 340,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _amount,
              autofocus: true,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Amount'),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 12),
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'cash', label: Text('Cash')),
                ButtonSegment(value: 'card', label: Text('Card')),
                ButtonSegment(value: 'transfer', label: Text('Transfer')),
              ],
              selected: {_method},
              onSelectionChanged: (s) => setState(() => _method = s.first),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _amountMinor > 0
              ? () => Navigator.of(
                  context,
                ).pop((amountMinor: _amountMinor, method: _method))
              : null,
          child: const Text('Save'),
        ),
      ],
    );
  }
}
