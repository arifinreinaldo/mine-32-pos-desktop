import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/di/providers.dart';
import '../../../core/money/money.dart';
import '../../catalog/domain/catalog_item.dart';
import '../../catalog/presentation/catalog_controller.dart';
import '../../inventory/presentation/inventory_controller.dart';
import '../domain/purchasing_models.dart';
import 'purchasing_controller.dart';

class _Line {
  final String variantId;
  final String description;
  int qty;
  final TextEditingController cost;
  _Line({
    required this.variantId,
    required this.description,
    required this.qty,
    required this.cost,
  });
}

/// Create a purchase order: pick a supplier, search parts, set qty + cost.
class PoCreateDialog extends ConsumerStatefulWidget {
  const PoCreateDialog({super.key});

  static Future<bool?> show(BuildContext context) {
    return showDialog<bool>(
      context: context,
      builder: (_) => const PoCreateDialog(),
    );
  }

  @override
  ConsumerState<PoCreateDialog> createState() => _PoCreateDialogState();
}

class _PoCreateDialogState extends ConsumerState<PoCreateDialog> {
  final _search = TextEditingController();
  final List<_Line> _lines = [];
  List<CatalogItem> _results = const [];
  String? _supplierId;
  String? _locationId;
  late final int _scale;
  bool _loading = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _scale = ref.read(currencyScaleProvider);
    _load();
  }

  Future<void> _load() async {
    final inventory = ref.read(inventoryRepositoryProvider);
    final locationId = await inventory.ensureDefaultLocation();
    final suppliers = await ref
        .read(purchasingRepositoryProvider)
        .watchSuppliers()
        .first;
    if (!mounted) return;
    setState(() {
      _locationId = locationId;
      _supplierId = suppliers.isNotEmpty ? suppliers.first.id : null;
      _loading = false;
    });
  }

  @override
  void dispose() {
    _search.dispose();
    for (final l in _lines) {
      l.cost.dispose();
    }
    super.dispose();
  }

  Future<void> _onSearch(String q) async {
    if (q.trim().isEmpty) {
      setState(() => _results = const []);
      return;
    }
    final items = await ref
        .read(catalogRepositoryProvider)
        .watch(query: q)
        .first;
    if (mounted) setState(() => _results = items);
  }

  void _addLine(CatalogItem item) {
    if (_lines.any((l) => l.variantId == item.variantId)) return;
    setState(() {
      _lines.add(
        _Line(
          variantId: item.variantId,
          description: '${item.productName} (${item.sku})',
          qty: 1,
          cost: TextEditingController(
            text: item.cost.toMajorString(scale: _scale),
          ),
        ),
      );
      _results = const [];
      _search.clear();
    });
  }

  int _lineCost(_Line l) {
    final t = l.cost.text.trim();
    if (t.isEmpty) return 0;
    try {
      return Money.fromMajor(t, scale: _scale).minorUnits;
    } on FormatException {
      return 0;
    }
  }

  int get _total => _lines.fold(0, (sum, l) => sum + l.qty * _lineCost(l));

  bool get _canCreate =>
      _supplierId != null && _locationId != null && _lines.isNotEmpty;

  Future<void> _create() async {
    setState(() => _saving = true);
    await ref
        .read(purchasingRepositoryProvider)
        .createPurchaseOrder(
          supplierId: _supplierId!,
          locationId: _locationId!,
          lines: [
            for (final l in _lines)
              PoLineInput(
                variantId: l.variantId,
                description: l.description,
                qty: l.qty,
                unitCostMinor: _lineCost(l),
              ),
          ],
        );
    if (mounted) Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final money = ref.watch(moneyFormatProvider);
    final suppliers = ref.watch(suppliersProvider).value ?? const [];

    return AlertDialog(
      title: const Text('New purchase order'),
      content: SizedBox(
        width: 560,
        child: _loading
            ? const SizedBox(
                height: 100,
                child: Center(child: CircularProgressIndicator()),
              )
            : Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (suppliers.isEmpty)
                    const Text('Add a supplier first.')
                  else
                    DropdownButtonFormField<String>(
                      initialValue: _supplierId,
                      decoration: const InputDecoration(labelText: 'Supplier'),
                      items: [
                        for (final s in suppliers)
                          DropdownMenuItem(value: s.id, child: Text(s.name)),
                      ],
                      onChanged: (v) => setState(() => _supplierId = v),
                    ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _search,
                    decoration: const InputDecoration(
                      prefixIcon: Icon(Icons.search),
                      hintText: 'Search a part to add',
                    ),
                    onChanged: _onSearch,
                  ),
                  if (_results.isNotEmpty)
                    SizedBox(
                      height: 140,
                      child: Card(
                        child: ListView(
                          shrinkWrap: true,
                          children: [
                            for (final item in _results)
                              ListTile(
                                dense: true,
                                title: Text(item.productName),
                                subtitle: Text(item.sku),
                                onTap: () => _addLine(item),
                              ),
                          ],
                        ),
                      ),
                    ),
                  const SizedBox(height: 8),
                  if (_lines.isEmpty)
                    const Padding(
                      padding: EdgeInsets.all(16),
                      child: Text('No items yet'),
                    )
                  else
                    ..._lines.map(_lineRow),
                  const Divider(),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Total'),
                      Text(
                        money.format(Money(_total)),
                        style: const TextStyle(fontWeight: FontWeight.bold),
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
          onPressed: (_canCreate && !_saving) ? _create : null,
          child: Text(_saving ? 'Creating…' : 'Create PO'),
        ),
      ],
    );
  }

  Widget _lineRow(_Line line) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(
            child: Text(line.description, overflow: TextOverflow.ellipsis),
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.remove_circle_outline, size: 18),
            onPressed: () => setState(() {
              if (line.qty > 1) line.qty--;
            }),
          ),
          Text('${line.qty}'),
          IconButton(
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.add_circle_outline, size: 18),
            onPressed: () => setState(() => line.qty++),
          ),
          SizedBox(
            width: 90,
            child: TextField(
              controller: line.cost,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                isDense: true,
                labelText: 'Cost',
              ),
              onChanged: (_) => setState(() {}),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close, size: 18),
            onPressed: () => setState(() {
              line.cost.dispose();
              _lines.remove(line);
            }),
          ),
        ],
      ),
    );
  }
}
