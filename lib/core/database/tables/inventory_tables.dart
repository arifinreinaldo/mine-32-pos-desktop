import 'package:drift/drift.dart';

import '../syncable_table.dart';

/// A stock location (store or warehouse). Master data (LWW).
class Locations extends Table with SyncableTable {
  TextColumn get name => text()();
  TextColumn get type => text().withDefault(const Constant('store'))();
  BoolColumn get isDefault => boolean().withDefault(const Constant(false))();
}

/// Append-only stock ledger. Each row is an immutable signed quantity change.
/// On-hand is the SUM of movements — so two devices adjusting stock offline both
/// count after sync (set-union of events; no lost updates). This is an **event**
/// sync entity (merged by insert-if-absent), never edited.
@TableIndex(name: 'idx_movement_variant', columns: {#variantId})
@TableIndex(name: 'idx_movement_location', columns: {#locationId})
class StockMovements extends Table with SyncableTable {
  TextColumn get variantId => text()();
  TextColumn get locationId => text()();

  /// Signed quantity delta (+receipt/-sale).
  IntColumn get qty => integer()();

  /// adjustment | sale | purchase | count | transfer_in | transfer_out | return
  TextColumn get reason => text()();

  /// Optional link back to the source document (sale, PO, transfer...).
  TextColumn get refType => text().nullable()();
  TextColumn get refId => text().nullable()();

  /// Unit cost (minor units) at the time of the movement, for valuation/COGS.
  IntColumn get unitCostMinor => integer().withDefault(const Constant(0))();
}
