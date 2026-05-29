import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/widgets/section_placeholder.dart';
import '../domain/stock_models.dart';
import 'inventory_controller.dart';
import 'stock_adjust_dialog.dart';

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
              const SizedBox(width: 110),
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
          SizedBox(
            width: 110,
            child: Align(
              alignment: Alignment.centerRight,
              child: OutlinedButton(
                onPressed: () => StockAdjustDialog.show(
                  context,
                  variantId: item.variantId,
                  label: item.sku,
                ),
                child: const Text('Adjust'),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
