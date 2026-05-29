import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/app_database.dart';
import 'inventory_controller.dart';

/// Adjust on-hand for a variant at a chosen location by setting a new count
/// (a counted adjustment is appended to the ledger).
class StockAdjustDialog extends ConsumerStatefulWidget {
  final String variantId;
  final String label;
  const StockAdjustDialog({
    super.key,
    required this.variantId,
    required this.label,
  });

  static Future<bool?> show(
    BuildContext context, {
    required String variantId,
    required String label,
  }) {
    return showDialog<bool>(
      context: context,
      builder: (_) => StockAdjustDialog(variantId: variantId, label: label),
    );
  }

  @override
  ConsumerState<StockAdjustDialog> createState() => _StockAdjustDialogState();
}

class _StockAdjustDialogState extends ConsumerState<StockAdjustDialog> {
  final _count = TextEditingController();
  List<Location> _locations = const [];
  String? _locationId;
  int _current = 0;
  bool _loading = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final repo = ref.read(inventoryRepositoryProvider);
    await repo.ensureDefaultLocation();
    final locations = await repo.watchLocations().first;
    final locationId = locations.isNotEmpty ? locations.first.id : null;
    final current = locationId == null
        ? 0
        : await repo.onHand(widget.variantId, locationId);
    if (!mounted) return;
    setState(() {
      _locations = locations;
      _locationId = locationId;
      _current = current;
      _count.text = current.toString();
      _loading = false;
    });
  }

  Future<void> _onLocationChanged(String? id) async {
    if (id == null) return;
    final current = await ref
        .read(inventoryRepositoryProvider)
        .onHand(widget.variantId, id);
    if (!mounted) return;
    setState(() {
      _locationId = id;
      _current = current;
      _count.text = current.toString();
    });
  }

  Future<void> _save() async {
    final target = int.tryParse(_count.text.trim());
    if (target == null || _locationId == null) return;
    setState(() => _saving = true);
    await ref
        .read(inventoryRepositoryProvider)
        .adjustTo(
          variantId: widget.variantId,
          locationId: _locationId!,
          targetQty: target,
        );
    if (mounted) Navigator.of(context).pop(true);
  }

  @override
  void dispose() {
    _count.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Adjust stock — ${widget.label}'),
      content: SizedBox(
        width: 360,
        child: _loading
            ? const SizedBox(
                height: 80,
                child: Center(child: CircularProgressIndicator()),
              )
            : Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  DropdownButtonFormField<String>(
                    initialValue: _locationId,
                    decoration: const InputDecoration(labelText: 'Location'),
                    items: [
                      for (final l in _locations)
                        DropdownMenuItem(value: l.id, child: Text(l.name)),
                    ],
                    onChanged: _onLocationChanged,
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _count,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      labelText: 'New on-hand count',
                      helperText: 'Current: $_current',
                    ),
                  ),
                ],
              ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _saving || _loading ? null : _save,
          child: const Text('Save'),
        ),
      ],
    );
  }
}
