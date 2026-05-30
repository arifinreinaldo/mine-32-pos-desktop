import 'package:csv/csv.dart';

import '../../../core/money/money.dart';
import '../domain/part_draft.dart';
import 'catalog_repository.dart';

/// Outcome of a CSV parts import.
class PartsImportResult {
  final int created;
  final int updated;
  final int skipped;
  final List<String> errors;
  const PartsImportResult({
    this.created = 0,
    this.updated = 0,
    this.skipped = 0,
    this.errors = const [],
  });

  int get total => created + updated + skipped;
  bool get hasErrors => errors.isNotEmpty;

  String summary() {
    if (total == 0 && errors.isNotEmpty) return errors.first;
    final parts = <String>[
      if (created > 0) '$created added',
      if (updated > 0) '$updated updated',
      if (skipped > 0) '$skipped skipped',
    ];
    if (parts.isEmpty) parts.add('nothing imported');
    return parts.join(', ');
  }
}

/// Imports parts from a CSV string into the catalog, matching existing parts by
/// SKU (update) or creating new ones. Header-driven and tolerant of column
/// order and common aliases. Money is parsed at the current currency [scale].
class PartsCsvImporter {
  final CatalogRepository catalog;
  final int scale;
  PartsCsvImporter({required this.catalog, required this.scale});

  /// Header aliases (normalised, lower-case) → canonical field.
  static const Map<String, List<String>> _aliases = {
    'name': ['name', 'part name', 'product', 'product name'],
    'sku': ['sku', 'code', 'part number', 'part no', 'partno', 'part_number'],
    'barcode': ['barcode', 'ean', 'upc'],
    'brand': ['brand', 'make', 'manufacturer'],
    'price': ['price', 'sell price', 'sale price', 'retail', 'sell_price'],
    'cost': ['cost', 'buy price', 'purchase price', 'buy_price'],
    'core': ['core', 'core charge', 'core_charge'],
    'description': ['description', 'desc', 'notes'],
    'active': ['active', 'enabled', 'is active', 'is_active'],
  };

  /// A ready-to-edit CSV template a user can fill in and re-import.
  static String template() {
    return 'name,sku,barcode,brand,price,cost,core_charge,description,active\n'
        'Brake Pad Set Front,BP-1001,8991234567890,Bosch,250000,150000,0,Front brake pads,true\n'
        'Oil Filter,OF-2002,,Denso,45000,25000,0,,true\n';
  }

  Future<PartsImportResult> import(String csv) async {
    final normalised = csv.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
    // autoDetect off → always comma-delimited; dynamicTyping off → all strings.
    final rows = Csv(autoDetect: false).decode(normalised);
    if (rows.isEmpty) {
      return const PartsImportResult(errors: ['The file is empty.']);
    }

    // Map canonical field -> column index from the header row.
    final header = rows.first.map((c) => _norm(c.toString())).toList();
    final col = <String, int>{};
    _aliases.forEach((field, names) {
      final idx = header.indexWhere(names.contains);
      if (idx >= 0) col[field] = idx;
    });
    if (!col.containsKey('name') || !col.containsKey('sku')) {
      return const PartsImportResult(
        errors: ['CSV must have "name" and "sku" columns.'],
      );
    }

    var created = 0, updated = 0, skipped = 0;
    final errors = <String>[];

    for (var i = 1; i < rows.length; i++) {
      final row = rows[i];
      final lineNo = i + 1; // 1-based, header is line 1
      String cell(String field) {
        final idx = col[field];
        if (idx == null || idx >= row.length) return '';
        return row[idx].toString().trim();
      }

      final name = cell('name');
      final sku = cell('sku');
      // Skip completely blank lines silently.
      if (name.isEmpty &&
          sku.isEmpty &&
          row.every((c) => '$c'.trim().isEmpty)) {
        continue;
      }
      if (name.isEmpty || sku.isEmpty) {
        errors.add('Line $lineNo: missing name or SKU.');
        skipped++;
        continue;
      }

      try {
        final existing = await catalog.getPartBySku(sku);
        Money money(String field, Money fallback) {
          final raw = cell(field);
          return raw.isEmpty ? fallback : Money.fromMajor(raw, scale: scale);
        }

        final brand = cell('brand');
        final desc = cell('description');
        final barcode = cell('barcode');
        final active = _bool(
          cell('active'),
          fallback: existing?.isActive ?? true,
        );

        final draft = (existing ?? PartDraft.empty()).copyWith(
          name: name,
          sku: sku,
          barcode: barcode.isEmpty ? null : barcode,
          brandName: brand.isEmpty ? null : brand,
          description: desc.isEmpty ? null : desc,
          price: money('price', existing?.price ?? const Money(0)),
          cost: money('cost', existing?.cost ?? const Money(0)),
          coreCharge: money('core', existing?.coreCharge ?? const Money(0)),
          isActive: active,
        );
        await catalog.savePart(draft);
        if (existing == null) {
          created++;
        } else {
          updated++;
        }
      } on FormatException catch (e) {
        errors.add('Line $lineNo: ${e.message}');
        skipped++;
      }
    }

    return PartsImportResult(
      created: created,
      updated: updated,
      skipped: skipped,
      errors: errors,
    );
  }

  static String _norm(String h) =>
      h.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');

  static bool _bool(String raw, {required bool fallback}) {
    final v = raw.trim().toLowerCase();
    if (v.isEmpty) return fallback;
    return v == 'true' || v == '1' || v == 'yes' || v == 'y' || v == 'active';
  }
}
