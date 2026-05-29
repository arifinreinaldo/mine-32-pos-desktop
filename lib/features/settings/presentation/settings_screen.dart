import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/settings_draft.dart';
import 'settings_controller.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  final _name = TextEditingController();
  final _legalName = TextEditingController();
  final _npwp = TextEditingController();
  final _address = TextEditingController();
  final _phone = TextEditingController();
  final _email = TextEditingController();
  final _receiptHeader = TextEditingController();
  final _receiptFooter = TextEditingController();
  String _currency = 'USD';
  int _scale = 2;
  bool _isPkp = false;
  bool _taxInclusive = true;
  bool _loaded = false;
  bool _saving = false;

  static const _currencies = ['USD', 'IDR', 'EUR', 'GBP', 'SGD', 'MYR', 'AUD'];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final s = await ref.read(settingsRepositoryProvider).get();
    if (s != null) {
      _name.text = s.name;
      _legalName.text = s.legalName ?? '';
      _npwp.text = s.taxNumber ?? '';
      _address.text = s.address ?? '';
      _phone.text = s.phone ?? '';
      _email.text = s.email ?? '';
      _receiptHeader.text = s.receiptHeader ?? '';
      _receiptFooter.text = s.receiptFooter ?? '';
      _currency = s.currency;
      _scale = s.currencyScale;
      _isPkp = s.isPkp;
      _taxInclusive = s.taxInclusive;
    }
    if (mounted) setState(() => _loaded = true);
  }

  @override
  void dispose() {
    for (final c in [
      _name,
      _legalName,
      _npwp,
      _address,
      _phone,
      _email,
      _receiptHeader,
      _receiptFooter,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  String? _t(TextEditingController c) =>
      c.text.trim().isEmpty ? null : c.text.trim();

  Future<void> _save() async {
    setState(() => _saving = true);
    await ref
        .read(settingsRepositoryProvider)
        .save(
          SettingsDraft(
            name: _name.text.trim().isEmpty
                ? 'My Auto Parts'
                : _name.text.trim(),
            legalName: _t(_legalName),
            npwp: _t(_npwp),
            isPkp: _isPkp,
            taxInclusive: _taxInclusive,
            address: _t(_address),
            phone: _t(_phone),
            email: _t(_email),
            currency: _currency,
            currencyScale: _scale,
            receiptHeader: _t(_receiptHeader),
            receiptFooter: _t(_receiptFooter),
          ),
        );
    if (mounted) {
      setState(() => _saving = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Settings saved')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (!_loaded) {
      return const Center(child: CircularProgressIndicator());
    }
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Settings', style: theme.textTheme.headlineSmall),
          const SizedBox(height: 16),
          Expanded(
            child: SingleChildScrollView(
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 640),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _section(theme, 'Business'),
                      _field(_name, 'Business name'),
                      _field(_legalName, 'Legal name'),
                      _field(_address, 'Address'),
                      Row(
                        children: [
                          Expanded(child: _field(_phone, 'Phone')),
                          const SizedBox(width: 12),
                          Expanded(child: _field(_email, 'Email')),
                        ],
                      ),
                      const SizedBox(height: 16),
                      _section(theme, 'Tax (Indonesia CoreTax)'),
                      _field(_npwp, 'NPWP (tax id)'),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Registered for VAT (PKP)'),
                        subtitle: const Text('Charge PPN on sales'),
                        value: _isPkp,
                        onChanged: (v) => setState(() => _isPkp = v),
                      ),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Prices include tax'),
                        value: _taxInclusive,
                        onChanged: (v) => setState(() => _taxInclusive = v),
                      ),
                      const SizedBox(height: 16),
                      _section(theme, 'Currency'),
                      Row(
                        children: [
                          Expanded(
                            child: DropdownButtonFormField<String>(
                              initialValue: _currency,
                              decoration: const InputDecoration(
                                labelText: 'Currency',
                              ),
                              items: [
                                for (final c in _currencies)
                                  DropdownMenuItem(value: c, child: Text(c)),
                              ],
                              onChanged: (v) {
                                if (v == null) return;
                                setState(() {
                                  _currency = v;
                                  _scale = v == 'IDR' ? 0 : 2;
                                });
                              },
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: InputDecorator(
                              decoration: const InputDecoration(
                                labelText: 'Decimal places',
                              ),
                              child: Text('$_scale'),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      _section(theme, 'Receipt'),
                      _field(_receiptHeader, 'Receipt header'),
                      _field(_receiptFooter, 'Receipt footer'),
                      const SizedBox(height: 20),
                      Align(
                        alignment: Alignment.centerRight,
                        child: FilledButton.icon(
                          onPressed: _saving ? null : _save,
                          icon: const Icon(Icons.save_outlined),
                          label: Text(_saving ? 'Saving…' : 'Save settings'),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _section(ThemeData theme, String title) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Text(
      title,
      style: theme.textTheme.titleMedium?.copyWith(
        fontWeight: FontWeight.w600,
        color: theme.colorScheme.primary,
      ),
    ),
  );

  Widget _field(TextEditingController c, String label) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: TextField(
      controller: c,
      decoration: InputDecoration(labelText: label),
    ),
  );
}
