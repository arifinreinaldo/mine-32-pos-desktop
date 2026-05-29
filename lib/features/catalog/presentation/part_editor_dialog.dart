import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/money/money.dart';
import '../domain/part_draft.dart';
import 'catalog_controller.dart';

/// Create/edit a simple part. Returns `true` from the dialog when saved.
class PartEditorDialog extends ConsumerStatefulWidget {
  final PartDraft initial;
  const PartEditorDialog({super.key, required this.initial});

  static Future<bool?> show(BuildContext context, {PartDraft? initial}) {
    return showDialog<bool>(
      context: context,
      builder: (_) => PartEditorDialog(initial: initial ?? PartDraft.empty()),
    );
  }

  @override
  ConsumerState<PartEditorDialog> createState() => _PartEditorDialogState();
}

class _PartEditorDialogState extends ConsumerState<PartEditorDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _sku;
  late final TextEditingController _barcode;
  late final TextEditingController _brand;
  late final TextEditingController _description;
  late final TextEditingController _price;
  late final TextEditingController _cost;
  late final TextEditingController _coreCharge;
  late bool _isActive;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final d = widget.initial;
    _name = TextEditingController(text: d.name);
    _sku = TextEditingController(text: d.sku);
    _barcode = TextEditingController(text: d.barcode ?? '');
    _brand = TextEditingController(text: d.brandName ?? '');
    _description = TextEditingController(text: d.description ?? '');
    _price = TextEditingController(text: d.price.toMajorString());
    _cost = TextEditingController(text: d.cost.toMajorString());
    _coreCharge = TextEditingController(text: d.coreCharge.toMajorString());
    _isActive = d.isActive;
  }

  @override
  void dispose() {
    for (final c in [
      _name,
      _sku,
      _barcode,
      _brand,
      _description,
      _price,
      _cost,
      _coreCharge,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  String? _required(String? v) =>
      (v == null || v.trim().isEmpty) ? 'Required' : null;

  String? _money(String? v) {
    if (v == null || v.trim().isEmpty) return null; // treated as 0
    return double.tryParse(v.trim()) == null ? 'Enter a number' : null;
  }

  Money _toMoney(TextEditingController c) {
    final t = c.text.trim();
    return t.isEmpty ? const Money(0) : Money.fromMajor(t);
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    final draft = widget.initial.copyWith(
      name: _name.text.trim(),
      sku: _sku.text.trim(),
      barcode: _barcode.text.trim().isEmpty ? null : _barcode.text.trim(),
      brandName: _brand.text.trim().isEmpty ? null : _brand.text.trim(),
      description: _description.text.trim().isEmpty
          ? null
          : _description.text.trim(),
      price: _toMoney(_price),
      cost: _toMoney(_cost),
      coreCharge: _toMoney(_coreCharge),
      isActive: _isActive,
    );
    await ref.read(catalogRepositoryProvider).savePart(draft);
    if (mounted) Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.initial.isNew ? 'Add part' : 'Edit part'),
      content: SizedBox(
        width: 480,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: _name,
                  decoration: const InputDecoration(labelText: 'Part name'),
                  validator: _required,
                  autofocus: true,
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _sku,
                        decoration: const InputDecoration(labelText: 'SKU'),
                        validator: _required,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextFormField(
                        controller: _barcode,
                        decoration: const InputDecoration(labelText: 'Barcode'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _brand,
                  decoration: const InputDecoration(labelText: 'Brand'),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _price,
                        decoration: const InputDecoration(labelText: 'Price'),
                        keyboardType: TextInputType.number,
                        validator: _money,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextFormField(
                        controller: _cost,
                        decoration: const InputDecoration(labelText: 'Cost'),
                        keyboardType: TextInputType.number,
                        validator: _money,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextFormField(
                        controller: _coreCharge,
                        decoration: const InputDecoration(
                          labelText: 'Core charge',
                        ),
                        keyboardType: TextInputType.number,
                        validator: _money,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _description,
                  decoration: const InputDecoration(labelText: 'Description'),
                  maxLines: 2,
                ),
                const SizedBox(height: 8),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Active'),
                  value: _isActive,
                  onChanged: (v) => setState(() => _isActive = v),
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(false),
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
