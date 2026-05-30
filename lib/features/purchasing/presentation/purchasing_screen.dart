import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/app_database.dart';
import '../../../core/di/providers.dart';
import '../../../core/money/money.dart';
import '../../../shared/widgets/amount_dialog.dart';
import 'po_create_dialog.dart';
import 'purchasing_controller.dart';
import 'supplier_editor_dialog.dart';

class PurchasingScreen extends StatelessWidget {
  const PurchasingScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return DefaultTabController(
      length: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Purchasing', style: theme.textTheme.headlineSmall),
            const SizedBox(height: 8),
            const TabBar(
              tabs: [
                Tab(text: 'Suppliers'),
                Tab(text: 'Purchase orders'),
              ],
            ),
            const Expanded(
              child: TabBarView(
                children: [_SuppliersTab(), _PurchaseOrdersTab()],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SuppliersTab extends ConsumerWidget {
  const _SuppliersTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final suppliers = ref.watch(suppliersProvider);
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: TextField(
                  decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.search),
                    hintText: 'Search suppliers',
                  ),
                  onChanged: (v) =>
                      ref.read(supplierQueryProvider.notifier).update(v),
                ),
              ),
              const SizedBox(width: 12),
              FilledButton.icon(
                onPressed: () => SupplierEditorDialog.show(context),
                icon: const Icon(Icons.add),
                label: const Text('Add supplier'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Expanded(
            child: suppliers.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('Error: $e')),
              data: (list) => list.isEmpty
                  ? const Center(child: Text('No suppliers'))
                  : ListView.separated(
                      itemCount: list.length,
                      separatorBuilder: (_, _) => const Divider(height: 1),
                      itemBuilder: (context, i) =>
                          _SupplierRow(supplier: list[i]),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PurchaseOrdersTab extends ConsumerWidget {
  const _PurchaseOrdersTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pos = ref.watch(purchaseOrdersProvider);
    final suppliers = ref.watch(suppliersProvider).value ?? const <Supplier>[];
    final money = ref.watch(moneyFormatProvider);
    final supplierName = {for (final s in suppliers) s.id: s.name};

    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton.icon(
              onPressed: () => PoCreateDialog.show(context),
              icon: const Icon(Icons.add),
              label: const Text('New PO'),
            ),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: pos.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('Error: $e')),
              data: (list) => list.isEmpty
                  ? const Center(child: Text('No purchase orders'))
                  : ListView.separated(
                      itemCount: list.length,
                      separatorBuilder: (_, _) => const Divider(height: 1),
                      itemBuilder: (context, i) {
                        final po = list[i];
                        return ListTile(
                          title: Text(
                            '${po.number} · ${supplierName[po.supplierId] ?? 'Supplier'}',
                          ),
                          subtitle: Text(po.status),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(money.format(Money(po.totalMinor))),
                              const SizedBox(width: 12),
                              if (po.status == 'ordered')
                                OutlinedButton(
                                  onPressed: () =>
                                      _receive(context, ref, po.id),
                                  child: const Text('Receive'),
                                )
                              else
                                Chip(
                                  label: Text(po.status),
                                  visualDensity: VisualDensity.compact,
                                ),
                            ],
                          ),
                        );
                      },
                    ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _receive(
    BuildContext context,
    WidgetRef ref,
    String poId,
  ) async {
    await ref.read(purchasingRepositoryProvider).receivePurchaseOrder(poId);
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Received — stock and AP updated')),
      );
    }
  }
}

class _SupplierRow extends ConsumerWidget {
  final Supplier supplier;
  const _SupplierRow({required this.supplier});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final money = ref.watch(moneyFormatProvider);
    final ap = ref.watch(supplierApProvider(supplier.id));
    final owed = ap.value ?? 0;
    return ListTile(
      leading: const Icon(Icons.local_shipping_outlined),
      title: Text(supplier.name),
      subtitle: Text(supplier.phone ?? supplier.email ?? '—'),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (owed > 0)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Text('AP ${money.format(Money(owed))}'),
            ),
          if (owed > 0)
            OutlinedButton(
              onPressed: () => _pay(context, ref, owed),
              child: const Text('Pay'),
            ),
          IconButton(
            tooltip: 'Edit',
            icon: const Icon(Icons.edit_outlined, size: 18),
            onPressed: () =>
                SupplierEditorDialog.show(context, initial: supplier),
          ),
        ],
      ),
      onTap: () => SupplierEditorDialog.show(context, initial: supplier),
    );
  }

  Future<void> _pay(BuildContext context, WidgetRef ref, int suggested) async {
    final result = await AmountDialog.show(
      context,
      title: 'Pay supplier',
      suggested: suggested > 0 ? suggested : null,
    );
    if (result == null) return;
    await ref
        .read(purchasingRepositoryProvider)
        .paySupplier(
          supplierId: supplier.id,
          amountMinor: result.amountMinor,
          method: result.method,
        );
    ref.invalidate(supplierApProvider(supplier.id));
    if (context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Payment recorded')));
    }
  }
}
