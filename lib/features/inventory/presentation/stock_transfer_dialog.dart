import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/app_database.dart';
import 'inventory_controller.dart';

/// Move stock for a variant from one location to another. Records two
/// conflict-free movements (transfer-out + transfer-in).
class StockTransferDialog extends ConsumerStatefulWidget {
  final String variantId;
  final String label;
  const StockTransferDialog({
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
      builder: (_) => StockTransferDialog(variantId: variantId, label: label),
    );
  }

  @override
  ConsumerState<StockTransferDialog> createState() =>
      _StockTransferDialogState();
}

class _StockTransferDialogState extends ConsumerState<StockTransferDialog> {
  final _qty = TextEditingController(text: '1');
  List<Location> _locations = const [];
  String? _fromId;
  String? _toId;
  int _fromOnHand = 0;
  bool _loading = true;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final repo = ref.read(inventoryRepositoryProvider);
    await repo.ensureDefaultLocation();
    final locations = await repo.listLocations();
    final from = locations.isNotEmpty ? locations.first.id : null;
    final to = locations.length > 1 ? locations[1].id : null;
    final onHand = from == null ? 0 : await repo.onHand(widget.variantId, from);
    if (!mounted) return;
    setState(() {
      _locations = locations;
      _fromId = from;
      _toId = to;
      _fromOnHand = onHand;
      _loading = false;
    });
  }

  Future<void> _onFromChanged(String? id) async {
    if (id == null) return;
    final onHand = await ref
        .read(inventoryRepositoryProvider)
        .onHand(widget.variantId, id);
    if (!mounted) return;
    setState(() {
      _fromId = id;
      _fromOnHand = onHand;
    });
  }

  Future<void> _save() async {
    final qty = int.tryParse(_qty.text.trim());
    if (qty == null || _fromId == null || _toId == null) {
      setState(() => _error = 'Pick locations and a quantity');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await ref
          .read(inventoryRepositoryProvider)
          .transfer(
            variantId: widget.variantId,
            fromLocationId: _fromId!,
            toLocationId: _toId!,
            qty: qty,
          );
      if (mounted) Navigator.of(context).pop(true);
    } on StateError catch (e) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = e.message;
        });
      }
    }
  }

  @override
  void dispose() {
    _qty.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final canTransfer = _locations.length > 1;
    return AlertDialog(
      title: Text('Transfer stock — ${widget.label}'),
      content: SizedBox(
        width: 380,
        child: _loading
            ? const SizedBox(
                height: 80,
                child: Center(child: CircularProgressIndicator()),
              )
            : !canTransfer
            ? const Text(
                'Add a second location first to transfer stock between them.',
              )
            : Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  DropdownButtonFormField<String>(
                    initialValue: _fromId,
                    decoration: InputDecoration(
                      labelText: 'From',
                      helperText: 'On hand: $_fromOnHand',
                    ),
                    items: [
                      for (final l in _locations)
                        DropdownMenuItem(value: l.id, child: Text(l.name)),
                    ],
                    onChanged: _onFromChanged,
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: _toId,
                    decoration: const InputDecoration(labelText: 'To'),
                    items: [
                      for (final l in _locations)
                        DropdownMenuItem(value: l.id, child: Text(l.name)),
                    ],
                    onChanged: (id) => setState(() => _toId = id),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _qty,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      labelText: 'Quantity',
                      errorText: _error,
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
          onPressed: (_saving || _loading || !canTransfer) ? null : _save,
          child: Text(_saving ? 'Transferring…' : 'Transfer'),
        ),
      ],
    );
  }
}
