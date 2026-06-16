import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/app_database.dart';
import '../../catalog/presentation/catalog_controller.dart';
import 'inventory_controller.dart';

/// A stock-count (stocktake) session at one location: list each part with its
/// current on-hand and an editable counted quantity, then post all differences
/// as `count` adjustments in one go.
class StockCountDialog extends ConsumerStatefulWidget {
  const StockCountDialog({super.key});

  static Future<int?> show(BuildContext context) {
    return showDialog<int>(
      context: context,
      builder: (_) => const StockCountDialog(),
    );
  }

  @override
  ConsumerState<StockCountDialog> createState() => _StockCountDialogState();
}

class _CountRow {
  final String variantId;
  final String sku;
  final String name;
  final int onHand;
  final TextEditingController counted;
  _CountRow(this.variantId, this.sku, this.name, this.onHand)
    : counted = TextEditingController(text: '$onHand');
}

class _StockCountDialogState extends ConsumerState<StockCountDialog> {
  List<Location> _locations = const [];
  String? _locationId;
  List<_CountRow> _rows = const [];
  bool _loading = true;
  bool _posting = false;

  @override
  void initState() {
    super.initState();
    _load(initial: true);
  }

  Future<void> _load({bool initial = false}) async {
    final inventory = ref.read(inventoryRepositoryProvider);
    if (initial) {
      await inventory.ensureDefaultLocation();
      _locations = await inventory.listLocations();
      _locationId = _locations.isNotEmpty ? _locations.first.id : null;
    }
    final items = await ref.read(catalogRepositoryProvider).list();
    final onHand = _locationId == null
        ? <String, int>{}
        : await inventory.stockAtLocation(_locationId!);
    for (final r in _rows) {
      r.counted.dispose();
    }
    if (!mounted) return;
    setState(() {
      _rows = [
        for (final i in items)
          _CountRow(
            i.variantId,
            i.sku,
            i.variantName == 'Default'
                ? i.productName
                : '${i.productName} — ${i.variantName}',
            onHand[i.variantId] ?? 0,
          ),
      ];
      _loading = false;
    });
  }

  @override
  void dispose() {
    for (final r in _rows) {
      r.counted.dispose();
    }
    super.dispose();
  }

  Future<void> _post() async {
    if (_locationId == null) return;
    final counts = <String, int>{};
    for (final r in _rows) {
      final n = int.tryParse(r.counted.text.trim());
      if (n != null) counts[r.variantId] = n;
    }
    setState(() => _posting = true);
    final adjusted = await ref
        .read(inventoryRepositoryProvider)
        .applyCount(locationId: _locationId!, counts: counts);
    if (mounted) Navigator.of(context).pop(adjusted);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      title: const Text('Stock count'),
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
                  if (_locations.length > 1)
                    DropdownButtonFormField<String>(
                      initialValue: _locationId,
                      decoration: const InputDecoration(labelText: 'Location'),
                      items: [
                        for (final l in _locations)
                          DropdownMenuItem(value: l.id, child: Text(l.name)),
                      ],
                      onChanged: (id) {
                        if (id == null) return;
                        setState(() {
                          _locationId = id;
                          _loading = true;
                        });
                        _load();
                      },
                    ),
                  const SizedBox(height: 8),
                  if (_rows.isEmpty)
                    const Padding(
                      padding: EdgeInsets.all(16),
                      child: Text('No parts to count.'),
                    )
                  else ...[
                    Row(
                      children: [
                        const Expanded(flex: 5, child: Text('Part')),
                        Expanded(
                          flex: 2,
                          child: Text(
                            'On hand',
                            textAlign: TextAlign.right,
                            style: theme.textTheme.labelMedium,
                          ),
                        ),
                        const SizedBox(width: 12),
                        SizedBox(
                          width: 90,
                          child: Text(
                            'Counted',
                            style: theme.textTheme.labelMedium,
                          ),
                        ),
                      ],
                    ),
                    const Divider(),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxHeight: 320),
                      child: ListView.separated(
                        shrinkWrap: true,
                        itemCount: _rows.length,
                        separatorBuilder: (_, _) => const Divider(height: 1),
                        itemBuilder: (context, i) {
                          final r = _rows[i];
                          return Padding(
                            padding: const EdgeInsets.symmetric(vertical: 4),
                            child: Row(
                              children: [
                                Expanded(
                                  flex: 5,
                                  child: Text(
                                    '${r.sku} · ${r.name}',
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                Expanded(
                                  flex: 2,
                                  child: Text(
                                    '${r.onHand}',
                                    textAlign: TextAlign.right,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                SizedBox(
                                  width: 90,
                                  child: TextField(
                                    controller: r.counted,
                                    keyboardType: TextInputType.number,
                                    textAlign: TextAlign.right,
                                    decoration: const InputDecoration(
                                      isDense: true,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ],
              ),
      ),
      actions: [
        TextButton(
          onPressed: _posting ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: (_posting || _loading || _rows.isEmpty) ? null : _post,
          child: Text(_posting ? 'Posting…' : 'Post count'),
        ),
      ],
    );
  }
}
