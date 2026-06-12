import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/di/providers.dart';
import '../../../shared/widgets/section_placeholder.dart';
import '../domain/catalog_item.dart';
import 'catalog_controller.dart';
import 'fitment_editor_dialog.dart';
import 'part_editor_dialog.dart';

class CatalogScreen extends ConsumerWidget {
  const CatalogScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final itemsAsync = ref.watch(catalogItemsProvider);
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Text('Catalog', style: theme.textTheme.headlineSmall),
              const Spacer(),
              SizedBox(
                width: 320,
                child: TextField(
                  decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.search),
                    hintText: 'Search SKU, name or barcode',
                  ),
                  onChanged: (v) =>
                      ref.read(catalogQueryProvider.notifier).update(v),
                ),
              ),
              const SizedBox(width: 12),
              FilledButton.icon(
                onPressed: () => PartEditorDialog.show(context),
                icon: const Icon(Icons.add),
                label: const Text('Add part'),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Expanded(
            child: itemsAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('Failed to load: $e')),
              data: (items) => items.isEmpty
                  ? const SectionPlaceholder(
                      title: 'No parts yet',
                      icon: Icons.inventory_2_outlined,
                      message: 'Add your first part to get started.',
                    )
                  : _CatalogTable(items: items),
            ),
          ),
        ],
      ),
    );
  }
}

class _CatalogTable extends ConsumerWidget {
  final List<CatalogItem> items;
  const _CatalogTable({required this.items});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _HeaderRow(),
        const Divider(height: 1),
        Expanded(
          child: ListView.separated(
            itemCount: items.length,
            separatorBuilder: (_, _) => const Divider(height: 1),
            itemBuilder: (context, i) => _ItemRow(item: items[i]),
          ),
        ),
      ],
    );
  }
}

class _HeaderRow extends StatelessWidget {
  const _HeaderRow();

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.labelMedium;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
      child: Row(
        children: [
          Expanded(flex: 2, child: Text('SKU', style: style)),
          Expanded(flex: 4, child: Text('Name', style: style)),
          Expanded(flex: 2, child: Text('Brand', style: style)),
          Expanded(
            flex: 2,
            child: Text('Price', style: style, textAlign: TextAlign.right),
          ),
          Expanded(
            flex: 2,
            child: Text('Margin', style: style, textAlign: TextAlign.right),
          ),
          const SizedBox(width: 144),
        ],
      ),
    );
  }
}

class _ItemRow extends ConsumerWidget {
  final CatalogItem item;
  const _ItemRow({required this.item});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final money = ref.watch(moneyFormatProvider);
    final margin = item.marginPct;
    return InkWell(
      onTap: () => _edit(context, ref),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
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
              flex: 4,
              child: Row(
                children: [
                  if (!item.isActive)
                    Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: Icon(
                        Icons.visibility_off_outlined,
                        size: 16,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  Flexible(
                    child: Text(
                      item.variantName == 'Default'
                          ? item.productName
                          : '${item.productName} — ${item.variantName}',
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
            Expanded(flex: 2, child: Text(item.brandName ?? '—')),
            Expanded(
              flex: 2,
              child: Text(money.format(item.price), textAlign: TextAlign.right),
            ),
            Expanded(
              flex: 2,
              child: Text(
                margin == null ? '—' : '${(margin * 100).toStringAsFixed(0)}%',
                textAlign: TextAlign.right,
              ),
            ),
            SizedBox(
              width: 144,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  IconButton(
                    tooltip: 'Fitment & cross-references',
                    visualDensity: VisualDensity.compact,
                    icon: const Icon(Icons.directions_car_outlined, size: 18),
                    onPressed: () => _fitment(context),
                  ),
                  IconButton(
                    tooltip: 'Edit',
                    visualDensity: VisualDensity.compact,
                    icon: const Icon(Icons.edit_outlined, size: 18),
                    onPressed: () => _edit(context, ref),
                  ),
                  IconButton(
                    tooltip: 'Delete',
                    visualDensity: VisualDensity.compact,
                    icon: const Icon(Icons.delete_outline, size: 18),
                    onPressed: () => _delete(context, ref),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _fitment(BuildContext context) {
    FitmentEditorDialog.show(
      context,
      variantId: item.variantId,
      partLabel: '${item.sku} · ${item.productName}',
    );
  }

  Future<void> _edit(BuildContext context, WidgetRef ref) async {
    final draft = await ref
        .read(catalogRepositoryProvider)
        .getPart(item.variantId);
    if (draft == null || !context.mounted) return;
    await PartEditorDialog.show(context, initial: draft);
  }

  Future<void> _delete(BuildContext context, WidgetRef ref) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete part?'),
        content: Text('Remove "${item.productName}" (${item.sku})?'),
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
      await ref.read(catalogRepositoryProvider).deletePart(item.variantId);
    }
  }
}
