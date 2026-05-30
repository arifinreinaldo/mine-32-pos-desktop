import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/app_database.dart';
import '../data/auto_parts_repository.dart';
import '../domain/auto_parts_models.dart';
import 'catalog_controller.dart';

/// Manage the vehicle fitment and cross-reference/interchange numbers for one
/// part variant. Every edit persists immediately (fitments and cross-references
/// are independent syncable entities), so there is no separate Save step.
class FitmentEditorDialog extends ConsumerWidget {
  final String variantId;
  final String partLabel;
  const FitmentEditorDialog({
    super.key,
    required this.variantId,
    required this.partLabel,
  });

  static Future<void> show(
    BuildContext context, {
    required String variantId,
    required String partLabel,
  }) {
    return showDialog<void>(
      context: context,
      builder: (_) =>
          FitmentEditorDialog(variantId: variantId, partLabel: partLabel),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final fitments = ref.watch(fitmentsProvider(variantId));
    final xrefs = ref.watch(crossReferencesProvider(variantId));

    return AlertDialog(
      title: const Text('Fitment & cross-references'),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                partLabel,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 16),
              _SectionHeader(
                icon: Icons.directions_car_outlined,
                label: 'Fits vehicles',
                onAdd: () => _addFitment(context, ref),
              ),
              fitments.when(
                loading: () => const _LoadingRow(),
                error: (e, _) => _ErrorRow('$e'),
                data: (rows) => rows.isEmpty
                    ? const _EmptyHint('No vehicles linked yet.')
                    : Column(
                        children: [
                          for (final f in rows)
                            _FitmentRow(fitment: f, variantId: variantId),
                        ],
                      ),
              ),
              const SizedBox(height: 20),
              _SectionHeader(
                icon: Icons.swap_horiz,
                label: 'Cross-references / interchange',
                onAdd: () => _addCrossRef(context, ref),
              ),
              xrefs.when(
                loading: () => const _LoadingRow(),
                error: (e, _) => _ErrorRow('$e'),
                data: (rows) => rows.isEmpty
                    ? const _EmptyHint('No cross-references yet.')
                    : Column(
                        children: [
                          for (final x in rows)
                            _CrossRefRow(xref: x, variantId: variantId),
                        ],
                      ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Close'),
        ),
      ],
    );
  }

  Future<void> _addFitment(BuildContext context, WidgetRef ref) async {
    final repo = ref.read(autoPartsRepositoryProvider);
    final draft = await showDialog<VehicleDraft>(
      context: context,
      builder: (_) => _AddFitmentDialog(existing: repo.listVehicles),
    );
    if (draft == null) return;
    final vehicleId = await repo.findOrCreateVehicle(draft);
    await repo.addFitment(variantId: variantId, vehicleId: vehicleId);
  }

  Future<void> _addCrossRef(BuildContext context, WidgetRef ref) async {
    final result = await showDialog<CrossRefInput>(
      context: context,
      builder: (_) => const _AddCrossRefDialog(),
    );
    if (result == null) return;
    await ref
        .read(autoPartsRepositoryProvider)
        .addCrossReference(
          variantId: variantId,
          otherNumber: result.number,
          otherBrand: result.brand,
          refType: result.type,
        );
  }
}

class _SectionHeader extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onAdd;
  const _SectionHeader({
    required this.icon,
    required this.label,
    required this.onAdd,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Icon(icon, size: 18, color: theme.colorScheme.primary),
        const SizedBox(width: 8),
        Text(label, style: theme.textTheme.titleSmall),
        const Spacer(),
        TextButton.icon(
          onPressed: onAdd,
          icon: const Icon(Icons.add, size: 18),
          label: const Text('Add'),
        ),
      ],
    );
  }
}

class _EmptyHint extends StatelessWidget {
  final String text;
  const _EmptyHint(this.text);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Text(
        text,
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

class _LoadingRow extends StatelessWidget {
  const _LoadingRow();
  @override
  Widget build(BuildContext context) => const Padding(
    padding: EdgeInsets.symmetric(vertical: 12),
    child: LinearProgressIndicator(),
  );
}

class _ErrorRow extends StatelessWidget {
  final String message;
  const _ErrorRow(this.message);
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 8),
    child: Text(
      'Failed: $message',
      style: TextStyle(color: Theme.of(context).colorScheme.error),
    ),
  );
}

class _FitmentRow extends ConsumerWidget {
  final FitmentView fitment;
  final String variantId;
  const _FitmentRow({required this.fitment, required this.variantId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      leading: const Icon(Icons.directions_car_outlined, size: 20),
      title: Text(fitment.vehicleLabel),
      subtitle: (fitment.note != null && fitment.note!.isNotEmpty)
          ? Text(fitment.note!)
          : null,
      trailing: IconButton(
        tooltip: 'Remove',
        icon: const Icon(Icons.close, size: 18),
        onPressed: () => ref
            .read(autoPartsRepositoryProvider)
            .removeFitment(fitment.fitmentId),
      ),
    );
  }
}

class _CrossRefRow extends ConsumerWidget {
  final CrossReferenceView xref;
  final String variantId;
  const _CrossRefRow({required this.xref, required this.variantId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final subtitleParts = <String>[
      if (xref.otherBrand != null && xref.otherBrand!.isNotEmpty)
        xref.otherBrand!,
      xref.refType.toUpperCase(),
    ];
    return ListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      leading: const Icon(Icons.swap_horiz, size: 20),
      title: Text(xref.otherNumber),
      subtitle: Text(subtitleParts.join(' · ')),
      trailing: IconButton(
        tooltip: 'Remove',
        icon: const Icon(Icons.close, size: 18),
        onPressed: () =>
            ref.read(autoPartsRepositoryProvider).removeCrossReference(xref.id),
      ),
    );
  }
}

/// Add-fitment form: pick an existing vehicle to prefill, or type a new
/// Year/Make/Model/Engine. Returns a [VehicleDraft] (the repository dedupes).
class _AddFitmentDialog extends StatefulWidget {
  final Future<List<Vehicle>> Function() existing;
  const _AddFitmentDialog({required this.existing});

  @override
  State<_AddFitmentDialog> createState() => _AddFitmentDialogState();
}

class _AddFitmentDialogState extends State<_AddFitmentDialog> {
  final _formKey = GlobalKey<FormState>();
  final _make = TextEditingController();
  final _model = TextEditingController();
  final _yearFrom = TextEditingController();
  final _yearTo = TextEditingController();
  final _engine = TextEditingController();
  List<Vehicle> _vehicles = const [];

  @override
  void initState() {
    super.initState();
    widget.existing().then((v) {
      if (mounted) setState(() => _vehicles = v);
    });
  }

  @override
  void dispose() {
    for (final c in [_make, _model, _yearFrom, _yearTo, _engine]) {
      c.dispose();
    }
    super.dispose();
  }

  String? _required(String? v) =>
      (v == null || v.trim().isEmpty) ? 'Required' : null;

  String? _year(String? v) {
    if (v == null || v.trim().isEmpty) return null;
    return int.tryParse(v.trim()) == null ? 'Year' : null;
  }

  void _prefill(Vehicle v) {
    _make.text = v.make;
    _model.text = v.model;
    _yearFrom.text = v.yearFrom?.toString() ?? '';
    _yearTo.text = v.yearTo?.toString() ?? '';
    _engine.text = v.engine ?? '';
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    int? parseYear(TextEditingController c) =>
        c.text.trim().isEmpty ? null : int.tryParse(c.text.trim());
    Navigator.of(context).pop(
      VehicleDraft(
        make: _make.text.trim(),
        model: _model.text.trim(),
        yearFrom: parseYear(_yearFrom),
        yearTo: parseYear(_yearTo),
        engine: _engine.text.trim().isEmpty ? null : _engine.text.trim(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Add fitment'),
      content: SizedBox(
        width: 420,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_vehicles.isNotEmpty) ...[
                  DropdownButtonFormField<String>(
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Reuse existing vehicle',
                    ),
                    items: [
                      for (final v in _vehicles)
                        DropdownMenuItem(
                          value: v.id,
                          child: Text(
                            AutoPartsRepository.vehicleLabel(v),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                    ],
                    onChanged: (id) {
                      if (id == null) return;
                      _prefill(_vehicles.firstWhere((v) => v.id == id));
                    },
                  ),
                  const SizedBox(height: 12),
                ],
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _make,
                        decoration: const InputDecoration(labelText: 'Make'),
                        validator: _required,
                        autofocus: true,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextFormField(
                        controller: _model,
                        decoration: const InputDecoration(labelText: 'Model'),
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
                        controller: _yearFrom,
                        decoration: const InputDecoration(
                          labelText: 'Year from',
                        ),
                        keyboardType: TextInputType.number,
                        validator: _year,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextFormField(
                        controller: _yearTo,
                        decoration: const InputDecoration(labelText: 'Year to'),
                        keyboardType: TextInputType.number,
                        validator: _year,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextFormField(
                        controller: _engine,
                        decoration: const InputDecoration(labelText: 'Engine'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _submit, child: const Text('Add')),
      ],
    );
  }
}

/// Result of the add-cross-reference form.
class CrossRefInput {
  final String number;
  final String? brand;
  final String type; // 'oem' | 'interchange'
  const CrossRefInput({required this.number, this.brand, required this.type});
}

class _AddCrossRefDialog extends StatefulWidget {
  const _AddCrossRefDialog();

  @override
  State<_AddCrossRefDialog> createState() => _AddCrossRefDialogState();
}

class _AddCrossRefDialogState extends State<_AddCrossRefDialog> {
  final _formKey = GlobalKey<FormState>();
  final _number = TextEditingController();
  final _brand = TextEditingController();
  String _type = 'interchange';

  @override
  void dispose() {
    _number.dispose();
    _brand.dispose();
    super.dispose();
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    Navigator.of(context).pop(
      CrossRefInput(
        number: _number.text.trim(),
        brand: _brand.text.trim().isEmpty ? null : _brand.text.trim(),
        type: _type,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Add cross-reference'),
      content: SizedBox(
        width: 420,
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: _number,
                decoration: const InputDecoration(
                  labelText: 'Part / interchange number',
                ),
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Required' : null,
                autofocus: true,
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _brand,
                      decoration: const InputDecoration(labelText: 'Brand'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      initialValue: _type,
                      decoration: const InputDecoration(labelText: 'Type'),
                      items: const [
                        DropdownMenuItem(
                          value: 'interchange',
                          child: Text('Interchange'),
                        ),
                        DropdownMenuItem(value: 'oem', child: Text('OEM')),
                      ],
                      onChanged: (v) =>
                          setState(() => _type = v ?? 'interchange'),
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
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _submit, child: const Text('Add')),
      ],
    );
  }
}
