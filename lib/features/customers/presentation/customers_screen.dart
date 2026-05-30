import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/app_database.dart';
import '../../../core/di/providers.dart';
import '../../../core/money/money.dart';
import 'customer_editor_dialog.dart';
import 'customer_vehicle_dialog.dart';
import 'customers_controller.dart';

class CustomersScreen extends ConsumerWidget {
  const CustomersScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return const Padding(
      padding: EdgeInsets.all(16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(width: 340, child: _ListPanel()),
          VerticalDivider(width: 24),
          Expanded(child: _DetailPanel()),
        ],
      ),
    );
  }
}

class _ListPanel extends ConsumerWidget {
  const _ListPanel();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final customers = ref.watch(customersProvider);
    final selected = ref.watch(selectedCustomerProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Text('Customers', style: theme.textTheme.headlineSmall),
            const Spacer(),
            FilledButton.icon(
              onPressed: () async {
                final id = await CustomerEditorDialog.show(context);
                if (id != null) {
                  ref.read(selectedCustomerProvider.notifier).select(id);
                }
              },
              icon: const Icon(Icons.add),
              label: const Text('Add'),
            ),
          ],
        ),
        const SizedBox(height: 12),
        TextField(
          decoration: const InputDecoration(
            prefixIcon: Icon(Icons.search),
            hintText: 'Search name or phone',
          ),
          onChanged: (v) => ref.read(customerQueryProvider.notifier).update(v),
        ),
        const SizedBox(height: 12),
        Expanded(
          child: customers.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Center(child: Text('Error: $e')),
            data: (list) => list.isEmpty
                ? const Center(child: Text('No customers'))
                : ListView.separated(
                    itemCount: list.length,
                    separatorBuilder: (_, _) => const Divider(height: 1),
                    itemBuilder: (context, i) {
                      final c = list[i];
                      return ListTile(
                        selected: c.id == selected,
                        title: Text(c.name),
                        subtitle: Text(c.phone ?? c.email ?? '—'),
                        onTap: () => ref
                            .read(selectedCustomerProvider.notifier)
                            .select(c.id),
                      );
                    },
                  ),
          ),
        ),
      ],
    );
  }
}

class _DetailPanel extends ConsumerWidget {
  const _DetailPanel();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final id = ref.watch(selectedCustomerProvider);
    if (id == null) {
      return const Center(child: Text('Select a customer'));
    }
    final list = ref.watch(customersProvider).value ?? const <Customer>[];
    final customer = list.where((c) => c.id == id).firstOrNull;
    if (customer == null) {
      return const Center(child: Text('Select a customer'));
    }
    return _CustomerDetail(customer: customer);
  }
}

class _CustomerDetail extends ConsumerWidget {
  final Customer customer;
  const _CustomerDetail({required this.customer});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final money = ref.watch(moneyFormatProvider);
    final ar = ref.watch(customerArProvider(customer.id));
    final vehicles = ref.watch(customerVehiclesProvider(customer.id));
    final history = ref.watch(customerHistoryProvider(customer.id));

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  customer.name,
                  style: theme.textTheme.headlineSmall,
                ),
              ),
              TextButton.icon(
                onPressed: () =>
                    CustomerEditorDialog.show(context, initial: customer),
                icon: const Icon(Icons.edit_outlined, size: 18),
                label: const Text('Edit'),
              ),
              IconButton(
                tooltip: 'Delete',
                onPressed: () => _delete(context, ref),
                icon: const Icon(Icons.delete_outline),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 24,
            runSpacing: 8,
            children: [
              _info('Phone', customer.phone ?? '—'),
              _info('Email', customer.email ?? '—'),
              _info('NPWP', customer.taxNumber ?? '—'),
              _info(
                'Credit limit',
                money.format(Money(customer.creditLimitMinor)),
              ),
              _info(
                'Balance (AR)',
                ar.when(
                  loading: () => '…',
                  error: (_, _) => '—',
                  data: (v) => money.format(Money(v)),
                ),
              ),
            ],
          ),
          if (customer.address != null) ...[
            const SizedBox(height: 8),
            _info('Address', customer.address!),
          ],
          const SizedBox(height: 20),
          Row(
            children: [
              Text('Vehicles', style: theme.textTheme.titleMedium),
              const Spacer(),
              TextButton.icon(
                onPressed: () =>
                    CustomerVehicleDialog.show(context, customer.id),
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Add vehicle'),
              ),
            ],
          ),
          vehicles.when(
            loading: () => const LinearProgressIndicator(),
            error: (e, _) => Text('Error: $e'),
            data: (list) => list.isEmpty
                ? const Text('No vehicles')
                : Column(
                    children: [
                      for (final v in list)
                        ListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          leading: const Icon(Icons.directions_car_outlined),
                          title: Text(v.description ?? v.plate ?? 'Vehicle'),
                          subtitle: Text(
                            [
                              if (v.plate != null) v.plate,
                              if (v.vin != null) 'VIN ${v.vin}',
                            ].whereType<String>().join(' • '),
                          ),
                          trailing: IconButton(
                            icon: const Icon(Icons.close, size: 18),
                            onPressed: () => ref
                                .read(customersRepositoryProvider)
                                .removeVehicle(v.id),
                          ),
                        ),
                    ],
                  ),
          ),
          const SizedBox(height: 20),
          Text('Recent purchases', style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          history.when(
            loading: () => const LinearProgressIndicator(),
            error: (e, _) => Text('Error: $e'),
            data: (sales) => sales.isEmpty
                ? const Text('No purchases yet')
                : Column(
                    children: [
                      for (final s in sales)
                        ListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          title: Text(s.number),
                          subtitle: Text(
                            DateTime.fromMillisecondsSinceEpoch(
                              s.createdAt,
                            ).toString().split('.').first,
                          ),
                          trailing: Text(money.format(Money(s.totalMinor))),
                        ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  Future<void> _delete(BuildContext context, WidgetRef ref) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete customer?'),
        content: Text('Remove "${customer.name}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirm == true) {
      await ref.read(customersRepositoryProvider).deleteCustomer(customer.id);
      ref.read(selectedCustomerProvider.notifier).select(null);
    }
  }

  Widget _info(String label, String value) {
    return Builder(
      builder: (context) {
        final theme = Theme.of(context);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            Text(value, style: theme.textTheme.bodyLarge),
          ],
        );
      },
    );
  }
}
