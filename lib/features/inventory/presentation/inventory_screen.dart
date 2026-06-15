import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/widgets/section_placeholder.dart';
import '../../purchasing/presentation/purchasing_controller.dart';
import '../domain/stock_models.dart';
import 'inventory_controller.dart';
import 'stock_adjust_dialog.dart';
import 'stock_transfer_dialog.dart';

/// Prompt for a name and create a new stock location.
Future<void> promptNewLocation(BuildContext context, WidgetRef ref) async {
  final controller = TextEditingController();
  final name = await showDialog<String>(
    context: context,
    builder: (_) => AlertDialog(
      title: const Text('New location'),
      content: TextField(
        controller: controller,
        autofocus: true,
        decoration: const InputDecoration(labelText: 'Location name'),
        onSubmitted: (v) => Navigator.of(context).pop(v.trim()),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(controller.text.trim()),
          child: const Text('Add'),
        ),
      ],
    ),
  );
  controller.dispose();
  if (name == null || name.isEmpty) return;
  await ref
      .read(inventoryRepositoryProvider)
      .upsertLocation(LocationDraft(name: name));
}

class InventoryScreen extends ConsumerWidget {
  const InventoryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final levels = ref.watch(stockLevelsProvider);
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Text('Stock', style: theme.textTheme.headlineSmall),
              const Spacer(),
              SizedBox(
                width: 320,
                child: TextField(
                  decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.search),
                    hintText: 'Search SKU or name',
                  ),
                  onChanged: (v) =>
                      ref.read(inventoryQueryProvider.notifier).update(v),
                ),
              ),
              const SizedBox(width: 12),
              OutlinedButton.icon(
                onPressed: () => promptNewLocation(context, ref),
                icon: const Icon(Icons.add_location_alt_outlined),
                label: const Text('New location'),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Expanded(
            child: levels.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('Failed to load: $e')),
              data: (items) => items.isEmpty
                  ? const SectionPlaceholder(
                      title: 'No stock yet',
                      icon: Icons.warehouse_outlined,
                      message:
                          'Add parts in the Catalog, then adjust stock here.',
                    )
                  : _StockTable(items: items),
            ),
          ),
        ],
      ),
    );
  }
}

class _StockTable extends StatelessWidget {
  final List<StockLevel> items;
  const _StockTable({required this.items});

  @override
  Widget build(BuildContext context) {
    final labelStyle = Theme.of(context).textTheme.labelMedium;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
          child: Row(
            children: [
              Expanded(flex: 2, child: Text('SKU', style: labelStyle)),
              Expanded(flex: 5, child: Text('Name', style: labelStyle)),
              Expanded(
                flex: 2,
                child: Text(
                  'On hand',
                  style: labelStyle,
                  textAlign: TextAlign.right,
                ),
              ),
              Expanded(
                flex: 2,
                child: Text(
                  'Incoming',
                  style: labelStyle,
                  textAlign: TextAlign.right,
                ),
              ),
              const SizedBox(width: 190),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: ListView.separated(
            itemCount: items.length,
            separatorBuilder: (_, _) => const Divider(height: 1),
            itemBuilder: (context, i) => _StockRow(item: items[i]),
          ),
        ),
      ],
    );
  }
}

class _StockRow extends ConsumerWidget {
  final StockLevel item;
  const _StockRow({required this.item});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final incoming =
        ref.watch(incomingByVariantProvider).asData?.value[item.variantId] ?? 0;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
      child: Row(
        children: [
          Expanded(
            flex: 2,
            child: Text(
              item.sku,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Expanded(
            flex: 5,
            child: Text(item.productName, overflow: TextOverflow.ellipsis),
          ),
          Expanded(
            flex: 2,
            child: Text(
              '${item.onHand}',
              textAlign: TextAlign.right,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w600,
                color: item.isLow ? theme.colorScheme.error : null,
              ),
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              incoming == 0 ? '—' : '+$incoming',
              textAlign: TextAlign.right,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: incoming > 0
                    ? theme.colorScheme.tertiary
                    : theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          SizedBox(
            width: 190,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                IconButton(
                  tooltip: 'Transfer between locations',
                  icon: const Icon(Icons.swap_horiz, size: 20),
                  onPressed: () => StockTransferDialog.show(
                    context,
                    variantId: item.variantId,
                    label: item.sku,
                  ),
                ),
                const SizedBox(width: 4),
                OutlinedButton(
                  onPressed: () => StockAdjustDialog.show(
                    context,
                    variantId: item.variantId,
                    label: item.sku,
                  ),
                  child: const Text('Adjust'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
