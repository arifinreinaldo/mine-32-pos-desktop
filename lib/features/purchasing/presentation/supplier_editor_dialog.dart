import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/app_database.dart';
import '../domain/purchasing_models.dart';
import 'purchasing_controller.dart';

/// Create/edit a supplier. Returns the saved supplier id.
class SupplierEditorDialog extends ConsumerStatefulWidget {
  final Supplier? initial;
  const SupplierEditorDialog({super.key, this.initial});

  static Future<String?> show(BuildContext context, {Supplier? initial}) {
    return showDialog<String>(
      context: context,
      builder: (_) => SupplierEditorDialog(initial: initial),
    );
  }

  @override
  ConsumerState<SupplierEditorDialog> createState() =>
      _SupplierEditorDialogState();
}

class _SupplierEditorDialogState extends ConsumerState<SupplierEditorDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _phone;
  late final TextEditingController _email;
  late final TextEditingController _npwp;
  late final TextEditingController _address;
  late final TextEditingController _terms;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final s = widget.initial;
    _name = TextEditingController(text: s?.name ?? '');
    _phone = TextEditingController(text: s?.phone ?? '');
    _email = TextEditingController(text: s?.email ?? '');
    _npwp = TextEditingController(text: s?.taxNumber ?? '');
    _address = TextEditingController(text: s?.address ?? '');
    _terms = TextEditingController(text: s?.terms ?? '');
  }

  @override
  void dispose() {
    for (final c in [_name, _phone, _email, _npwp, _address, _terms]) {
      c.dispose();
    }
    super.dispose();
  }

  String? _t(TextEditingController c) =>
      c.text.trim().isEmpty ? null : c.text.trim();

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    final id = await ref
        .read(purchasingRepositoryProvider)
        .saveSupplier(
          SupplierDraft(
            id: widget.initial?.id,
            name: _name.text.trim(),
            phone: _t(_phone),
            email: _t(_email),
            npwp: _t(_npwp),
            address: _t(_address),
            terms: _t(_terms),
          ),
        );
    if (mounted) Navigator.of(context).pop(id);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.initial == null ? 'Add supplier' : 'Edit supplier'),
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
                  controller: _terms,
                  decoration: const InputDecoration(
                    labelText: 'Terms (e.g. Net 30)',
                  ),
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
