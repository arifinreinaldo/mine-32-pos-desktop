import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/di/providers.dart';
import '../../../core/money/money.dart';
import '../domain/catalog_item.dart';
import '../domain/part_draft.dart';
import 'catalog_controller.dart';
import 'fitment_editor_dialog.dart';

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
  late final TextEditingController _wholesale;
  late final TextEditingController _cost;
  late final TextEditingController _coreCharge;
  late bool _isActive;
  late final int _scale;
  bool _saving = false;
  Future<List<CatalogItem>>? _siblings;

  @override
  void initState() {
    super.initState();
    _scale = ref.read(currencyScaleProvider);
    final d = widget.initial;
    if (d.productId != null) {
      _siblings = ref
          .read(catalogRepositoryProvider)
          .itemsForProduct(d.productId!);
    }
    _name = TextEditingController(text: d.name);
    _sku = TextEditingController(text: d.sku);
    _barcode = TextEditingController(text: d.barcode ?? '');
    _brand = TextEditingController(text: d.brandName ?? '');
    _description = TextEditingController(text: d.description ?? '');
    _price = TextEditingController(text: d.price.toMajorString(scale: _scale));
    _wholesale = TextEditingController(
      text: d.wholesalePrice.minorUnits == 0
          ? ''
          : d.wholesalePrice.toMajorString(scale: _scale),
    );
    _cost = TextEditingController(text: d.cost.toMajorString(scale: _scale));
    _coreCharge = TextEditingController(
      text: d.coreCharge.toMajorString(scale: _scale),
    );
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
      _wholesale,
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
    if (t.isEmpty) return const Money(0);
    try {
      return Money.fromMajor(t, scale: _scale);
    } on FormatException {
      return const Money(0);
    }
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
      wholesalePrice: _toMoney(_wholesale),
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
                  controller: _wholesale,
                  decoration: const InputDecoration(
                    labelText: 'Wholesale price',
                    helperText:
                        'Charged to wholesale customers (blank = retail)',
                  ),
                  keyboardType: TextInputType.number,
                  validator: _money,
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
                if (!widget.initial.isNew) ...[
                  const Divider(height: 16),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: OutlinedButton.icon(
                      onPressed: () => FitmentEditorDialog.show(
                        context,
                        variantId: widget.initial.variantId!,
                        partLabel:
                            '${widget.initial.sku} · ${widget.initial.name}',
                      ),
                      icon: const Icon(Icons.directions_car_outlined, size: 18),
                      label: const Text('Vehicle fitment & cross-references'),
                    ),
                  ),
                  const SizedBox(height: 8),
                  _variantsSection(context),
                ],
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

  /// Sibling variants of this product (shown when editing): each is its own
  /// sellable catalog row; add more via 'Add variant'.
  Widget _variantsSection(BuildContext context) {
    final theme = Theme.of(context);
    final money = ref.watch(moneyFormatProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Icon(
              Icons.layers_outlined,
              size: 18,
              color: theme.colorScheme.primary,
            ),
            const SizedBox(width: 8),
            Text('Variants', style: theme.textTheme.titleSmall),
            const Spacer(),
            TextButton.icon(
              onPressed: _addVariant,
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Add variant'),
            ),
          ],
        ),
        FutureBuilder<List<CatalogItem>>(
          future: _siblings,
          builder: (context, snap) {
            final items = snap.data;
            if (items == null) {
              return const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: LinearProgressIndicator(),
              );
            }
            return Column(
              children: [
                for (final v in items)
                  ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(
                      v.variantId == widget.initial.variantId
                          ? Icons.radio_button_checked
                          : Icons.radio_button_off,
                      size: 18,
                    ),
                    title: Text('${v.variantName} · ${v.sku}'),
                    trailing: Text(money.format(v.price)),
                  ),
              ],
            );
          },
        ),
      ],
    );
  }

  Future<void> _addVariant() async {
    final added = await showDialog<bool>(
      context: context,
      builder: (_) => _AddVariantDialog(parent: widget.initial),
    );
    if (added == true && mounted) {
      setState(() {
        _siblings = ref
            .read(catalogRepositoryProvider)
            .itemsForProduct(widget.initial.productId!);
      });
    }
  }
}

/// Add another sellable variant to an existing product (own name, SKU,
/// barcode and prices; shares the product's name/brand/description).
class _AddVariantDialog extends ConsumerStatefulWidget {
  final PartDraft parent;
  const _AddVariantDialog({required this.parent});

  @override
  ConsumerState<_AddVariantDialog> createState() => _AddVariantDialogState();
}

class _AddVariantDialogState extends ConsumerState<_AddVariantDialog> {
  final _formKey = GlobalKey<FormState>();
  final _variantName = TextEditingController();
  final _sku = TextEditingController();
  final _barcode = TextEditingController();
  late final TextEditingController _price;
  late final TextEditingController _cost;
  late final int _scale;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _scale = ref.read(currencyScaleProvider);
    // Prefill prices from the variant being edited — usually close.
    _price = TextEditingController(
      text: widget.parent.price.toMajorString(scale: _scale),
    );
    _cost = TextEditingController(
      text: widget.parent.cost.toMajorString(scale: _scale),
    );
  }

  @override
  void dispose() {
    for (final c in [_variantName, _sku, _barcode, _price, _cost]) {
      c.dispose();
    }
    super.dispose();
  }

  String? _required(String? v) =>
      (v == null || v.trim().isEmpty) ? 'Required' : null;

  Money _toMoney(TextEditingController c) {
    final t = c.text.trim();
    if (t.isEmpty) return const Money(0);
    try {
      return Money.fromMajor(t, scale: _scale);
    } on FormatException {
      return const Money(0);
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    await ref
        .read(catalogRepositoryProvider)
        .savePart(
          PartDraft(
            productId: widget.parent.productId,
            name: widget.parent.name,
            brandName: widget.parent.brandName,
            description: widget.parent.description,
            variantName: _variantName.text.trim(),
            sku: _sku.text.trim(),
            barcode: _barcode.text.trim().isEmpty ? null : _barcode.text.trim(),
            price: _toMoney(_price),
            cost: _toMoney(_cost),
            coreCharge: const Money(0),
          ),
        );
    if (mounted) Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Add variant — ${widget.parent.name}'),
      content: SizedBox(
        width: 420,
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _variantName,
                      decoration: const InputDecoration(
                        labelText: 'Variant name',
                        hintText: 'e.g. Rear, Ceramic',
                      ),
                      validator: _required,
                      autofocus: true,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextFormField(
                      controller: _sku,
                      decoration: const InputDecoration(labelText: 'SKU'),
                      validator: _required,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _price,
                      decoration: const InputDecoration(labelText: 'Price'),
                      keyboardType: TextInputType.number,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextFormField(
                      controller: _cost,
                      decoration: const InputDecoration(labelText: 'Cost'),
                      keyboardType: TextInputType.number,
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
            ],
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
          child: Text(_saving ? 'Saving…' : 'Add'),
        ),
      ],
    );
  }
}
