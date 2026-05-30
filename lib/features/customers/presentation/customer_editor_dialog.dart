import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/app_database.dart';
import '../../../core/di/providers.dart';
import '../../../core/money/money.dart';
import '../domain/customer_draft.dart';
import 'customers_controller.dart';

/// Create/edit a customer. Returns the saved customer id.
class CustomerEditorDialog extends ConsumerStatefulWidget {
  final Customer? initial;
  const CustomerEditorDialog({super.key, this.initial});

  static Future<String?> show(BuildContext context, {Customer? initial}) {
    return showDialog<String>(
      context: context,
      builder: (_) => CustomerEditorDialog(initial: initial),
    );
  }

  @override
  ConsumerState<CustomerEditorDialog> createState() =>
      _CustomerEditorDialogState();
}

class _CustomerEditorDialogState extends ConsumerState<CustomerEditorDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _phone;
  late final TextEditingController _email;
  late final TextEditingController _npwp;
  late final TextEditingController _address;
  late final TextEditingController _creditLimit;
  late final TextEditingController _notes;
  late final int _scale;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _scale = ref.read(currencyScaleProvider);
    final c = widget.initial;
    _name = TextEditingController(text: c?.name ?? '');
    _phone = TextEditingController(text: c?.phone ?? '');
    _email = TextEditingController(text: c?.email ?? '');
    _npwp = TextEditingController(text: c?.taxNumber ?? '');
    _address = TextEditingController(text: c?.address ?? '');
    _creditLimit = TextEditingController(
      text: Money(c?.creditLimitMinor ?? 0).toMajorString(scale: _scale),
    );
    _notes = TextEditingController(text: c?.notes ?? '');
  }

  @override
  void dispose() {
    for (final c in [
      _name,
      _phone,
      _email,
      _npwp,
      _address,
      _creditLimit,
      _notes,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  String? _t(TextEditingController c) =>
      c.text.trim().isEmpty ? null : c.text.trim();

  int _creditLimitMinor() {
    final t = _creditLimit.text.trim();
    if (t.isEmpty) return 0;
    try {
      return Money.fromMajor(t, scale: _scale).minorUnits;
    } on FormatException {
      return 0;
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    final id = await ref
        .read(customersRepositoryProvider)
        .saveCustomer(
          CustomerDraft(
            id: widget.initial?.id,
            name: _name.text.trim(),
            phone: _t(_phone),
            email: _t(_email),
            npwp: _t(_npwp),
            address: _t(_address),
            creditLimitMinor: _creditLimitMinor(),
            notes: _t(_notes),
          ),
        );
    if (mounted) Navigator.of(context).pop(id);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.initial == null ? 'Add customer' : 'Edit customer'),
      content: SizedBox(
        width: 460,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: _name,
                  decoration: const InputDecoration(labelText: 'Name'),
                  autofocus: true,
                  validator: (v) =>
                      (v == null || v.trim().isEmpty) ? 'Required' : null,
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _phone,
                        decoration: const InputDecoration(labelText: 'Phone'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextFormField(
                        controller: _email,
                        decoration: const InputDecoration(labelText: 'Email'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _npwp,
                  decoration: const InputDecoration(labelText: 'NPWP (tax id)'),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _address,
                  decoration: const InputDecoration(labelText: 'Address'),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _creditLimit,
                  decoration: const InputDecoration(labelText: 'Credit limit'),
                  keyboardType: TextInputType.number,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _notes,
                  decoration: const InputDecoration(labelText: 'Notes'),
                  maxLines: 2,
                ),
              ],
            ),
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
