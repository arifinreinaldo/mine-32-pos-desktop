import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/app_database.dart';
import 'accounting_controller.dart';

/// Format basis points as a percent string (1100 -> "11", 1050 -> "10.5").
String formatBasisPoints(int basisPoints) {
  final v = basisPoints / 100;
  return v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toString();
}

/// Create or edit a tax rate (e.g. PPN 11%). Marking it default clears the flag
/// on the others so checkout always has exactly one default.
class TaxRateEditorDialog extends ConsumerStatefulWidget {
  final TaxRate? initial;
  const TaxRateEditorDialog({super.key, this.initial});

  static Future<void> show(BuildContext context, {TaxRate? initial}) {
    return showDialog<void>(
      context: context,
      builder: (_) => TaxRateEditorDialog(initial: initial),
    );
  }

  @override
  ConsumerState<TaxRateEditorDialog> createState() =>
      _TaxRateEditorDialogState();
}

class _TaxRateEditorDialogState extends ConsumerState<TaxRateEditorDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _percent;
  late final TextEditingController _taxType;
  late bool _inclusive;
  late bool _isDefault;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final r = widget.initial;
    _name = TextEditingController(text: r?.name ?? '');
    _percent = TextEditingController(
      text: r == null ? '' : formatBasisPoints(r.basisPoints),
    );
    _taxType = TextEditingController(text: r?.taxType ?? 'PPN');
    _inclusive = r?.inclusive ?? true;
    _isDefault = r?.isDefault ?? false;
  }

  @override
  void dispose() {
    _name.dispose();
    _percent.dispose();
    _taxType.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    final basisPoints = (double.parse(_percent.text.trim()) * 100).round();
    await ref
        .read(accountingRepositoryProvider)
        .saveTaxRate(
          id: widget.initial?.id,
          name: _name.text.trim(),
          basisPoints: basisPoints,
          inclusive: _inclusive,
          isDefault: _isDefault,
          taxType: _taxType.text.trim().isEmpty ? 'PPN' : _taxType.text.trim(),
        );
    // Checkout reads the default rate from a cached provider; refresh it.
    ref.invalidate(defaultTaxRateProvider);
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.initial == null ? 'Add tax rate' : 'Edit tax rate'),
      content: SizedBox(
        width: 420,
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: _name,
                decoration: const InputDecoration(labelText: 'Name'),
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Required' : null,
                autofocus: true,
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _percent,
                      decoration: const InputDecoration(
                        labelText: 'Rate',
                        suffixText: '%',
                      ),
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      validator: (v) {
                        final d = double.tryParse((v ?? '').trim());
                        if (d == null || d < 0) return 'Enter a percent';
                        return null;
                      },
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextFormField(
                      controller: _taxType,
                      decoration: const InputDecoration(labelText: 'Type'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Prices include this tax'),
                value: _inclusive,
                onChanged: (v) => setState(() => _inclusive = v),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Default at checkout'),
                value: _isDefault,
                onChanged: (v) => setState(() => _isDefault = v),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: Text(_saving ? 'Saving…' : 'Save'),
        ),
      ],
    );
  }
}
