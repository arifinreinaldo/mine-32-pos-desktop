import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'customers_controller.dart';

/// Add a vehicle to a customer.
class CustomerVehicleDialog extends ConsumerStatefulWidget {
  final String customerId;
  const CustomerVehicleDialog({super.key, required this.customerId});

  static Future<bool?> show(BuildContext context, String customerId) {
    return showDialog<bool>(
      context: context,
      builder: (_) => CustomerVehicleDialog(customerId: customerId),
    );
  }

  @override
  ConsumerState<CustomerVehicleDialog> createState() =>
      _CustomerVehicleDialogState();
}

class _CustomerVehicleDialogState extends ConsumerState<CustomerVehicleDialog> {
  final _plate = TextEditingController();
  final _vin = TextEditingController();
  final _description = TextEditingController();
  bool _saving = false;

  @override
  void dispose() {
    _plate.dispose();
    _vin.dispose();
    _description.dispose();
    super.dispose();
  }

  String? _t(TextEditingController c) =>
      c.text.trim().isEmpty ? null : c.text.trim();

  Future<void> _save() async {
    setState(() => _saving = true);
    await ref
        .read(customersRepositoryProvider)
        .addVehicle(
          customerId: widget.customerId,
          plate: _t(_plate),
          vin: _t(_vin),
          description: _t(_description),
        );
    if (mounted) Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Add vehicle'),
      content: SizedBox(
        width: 360,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _description,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: 'Description (e.g. Toyota Corolla 2015)',
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _plate,
                    decoration: const InputDecoration(labelText: 'Plate'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: _vin,
                    decoration: const InputDecoration(labelText: 'VIN'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: const Text('Add'),
        ),
      ],
    );
  }
}
