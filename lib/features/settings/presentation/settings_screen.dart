import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/di/providers.dart';
import '../../catalog/data/parts_csv_import.dart';
import '../../catalog/presentation/catalog_controller.dart';
import '../../customers/presentation/customers_controller.dart';
import '../../inventory/presentation/inventory_controller.dart';
import '../../purchasing/presentation/purchasing_controller.dart';
import '../data/sample_data.dart';
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

  Future<void> _loadSampleData() async {
    final count = await SampleData.load(
      catalog: ref.read(catalogRepositoryProvider),
      inventory: ref.read(inventoryRepositoryProvider),
      autoParts: ref.read(autoPartsRepositoryProvider),
      purchasing: ref.read(purchasingRepositoryProvider),
      customers: ref.read(customersRepositoryProvider),
    );
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            count == 0
                ? 'Sample data already present'
                : 'Loaded $count sample parts (with stock, supplier & customer)',
          ),
        ),
      );
    }
  }

  Future<void> _importPartsCsv() async {
    final picked = await FilePicker.pickFiles(
      dialogTitle: 'Import parts from CSV',
      type: FileType.custom,
      allowedExtensions: const ['csv'],
      withData: true,
    );
    final bytes = picked?.files.firstOrNull?.bytes;
    if (bytes == null) return;
    final importer = PartsCsvImporter(
      catalog: ref.read(catalogRepositoryProvider),
      scale: ref.read(currencyScaleProvider),
    );
    final result = await importer.import(
      utf8.decode(bytes, allowMalformed: true),
    );
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Import parts'),
        content: SizedBox(
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(result.summary()),
              if (result.hasErrors) ...[
                const SizedBox(height: 12),
                Text(
                  '${result.errors.length} problem(s):',
                  style: Theme.of(context).textTheme.labelLarge,
                ),
                const SizedBox(height: 4),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 200),
                  child: SingleChildScrollView(
                    child: Text(result.errors.join('\n')),
                  ),
                ),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Future<void> _backup() async {
    final bytes = await ref.read(backupServiceProvider).exportBytes();
    final now = DateTime.now();
    final stamp =
        '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
    final path = await FilePicker.saveFile(
      dialogTitle: 'Save data backup',
      fileName: 'mine32-backup-$stamp.json',
      bytes: Uint8List.fromList(bytes),
    );
    if (mounted && path != null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Backup saved')));
    }
  }

  Future<void> _restore() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Restore from backup?'),
        content: const Text(
          'This merges the backup into the current data. Existing records are '
          'updated by last-write-wins; nothing is deleted. Continue?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Restore'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    final picked = await FilePicker.pickFiles(
      dialogTitle: 'Choose a backup file',
      type: FileType.custom,
      allowedExtensions: const ['json'],
      withData: true,
    );
    final bytes = picked?.files.firstOrNull?.bytes;
    if (bytes == null) return;
    try {
      final result = await ref.read(backupServiceProvider).importBytes(bytes);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Restored ${result.rows} record(s) from ${result.tables} table(s)',
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Restore failed: $e')));
      }
    }
  }

  Future<void> _downloadCsvTemplate() async {
    final path = await FilePicker.saveFile(
      dialogTitle: 'Save parts CSV template',
      fileName: 'parts-template.csv',
      bytes: Uint8List.fromList(utf8.encode(PartsCsvImporter.template())),
    );
    if (mounted && path != null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Template saved')));
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
                      const SizedBox(height: 16),
                      _section(theme, 'Data'),
                      Wrap(
                        spacing: 12,
                        runSpacing: 8,
                        children: [
                          OutlinedButton.icon(
                            onPressed: _importPartsCsv,
                            icon: const Icon(Icons.upload_file_outlined),
                            label: const Text('Import parts (CSV)'),
                          ),
                          OutlinedButton.icon(
                            onPressed: _downloadCsvTemplate,
                            icon: const Icon(Icons.download_outlined),
                            label: const Text('CSV template'),
                          ),
                          OutlinedButton.icon(
                            onPressed: _loadSampleData,
                            icon: const Icon(Icons.dataset_outlined),
                            label: const Text('Load sample data'),
                          ),
                          OutlinedButton.icon(
                            onPressed: _backup,
                            icon: const Icon(Icons.backup_outlined),
                            label: const Text('Back up data'),
                          ),
                          OutlinedButton.icon(
                            onPressed: _restore,
                            icon: const Icon(Icons.restore_outlined),
                            label: const Text('Restore data'),
                          ),
                        ],
                      ),
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
