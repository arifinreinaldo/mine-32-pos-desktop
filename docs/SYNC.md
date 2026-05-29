# Sync — Serverless, Offline-First

**Requirement:** offline-first with sync capability, **no backend server**. Each
device is autonomous; the local SQLite DB is the source of truth. Devices share
state by exchanging portable **change bundles** through a **shared/cloud-synced
folder** (OneDrive / Dropbox / Google Drive / LAN share) or removable media.
There is no central authority and no online dependency.

## Mental model

Think of it like git for rows: every device keeps an append-only **change log**
(oplog). Sync = export your new changes as a file into a shared folder, and
import everyone else's files. Merge is deterministic so any order of exchange
converges to the same state (eventual consistency).

## Building blocks

### 1. Identity & ordering — Hybrid Logical Clock (HLC)

- Each install has a stable `device_id` (UUID).
- An `Hlc` = `physicalMillis . counter . deviceId`, packed into a fixed-width,
  lexicographically-sortable string. It advances past wall-clock skew and breaks
  ties by `deviceId`, giving a **total order** across devices with no server.
- Every write stamps the row's `updated_hlc` and the change record's `hlc`.

### 2. The change log (outbox)

Every repository mutation, in one transaction, both (a) writes the Drift row and
(b) appends a `change_log` record:
`{ id, table_name, row_id, op: upsert|delete, payload: <row snapshot json>, hlc, device_id, exported: false }`.

The change log IS the sync payload — there is no separate "dirty flag" scan.

### 3. Bundles

- **Export:** collect `change_log` rows where `exported = false`, wrap in an
  envelope `{ schema_version, device_id, from_hlc, to_hlc, changes[] }`, write to
  `<shared>/mine32-sync/<device_id>/<to_hlc>.bundle.json` (optionally gzip), mark
  exported. Bundles are immutable and named by HLC so peers can resume.
- **Import:** for every peer folder, read bundles newer than the cursor we stored
  for that peer in `sync_meta`; apply; advance the cursor. Idempotent: each
  applied `change_id` is recorded in `applied_changes`, so re-importing is a no-op.

### 4. Merge / conflict resolution (deterministic)

Resolution depends on the table **kind** (see `docs/DATA_MODEL.md`):

- **Master data (M) — Last-Write-Wins by HLC.** On an incoming upsert, compare
  `incoming.hlc` with the local row's `updated_hlc`. Apply only if strictly
  greater. Because HLC is a total order (deviceId tiebreak), all devices pick the
  same winner regardless of arrival order. Deletes are tombstones (`deleted_at`),
  which also obey LWW so a late update can't resurrect a deleted row.
- **Event data (E) — set union.** Stock movements, posted sales/lines, payments,
  journal lines are immutable and identified by UUID. Applying = insert-if-absent.
  Union of sets is commutative & idempotent ⇒ conflict-free by construction.
- **Projections (P) — recompute, never sync.** On-hand stock and account balances
  are derived from event tables and rebuilt locally after import. This is why
  concurrent stock changes on two devices never "lose" each other: each is a
  movement; the projection is their sum.

This hybrid is the key insight: anything where concurrent edits must *both* count
(stock, money) is modeled as **events**; anything that is a current-value fact
(a product's price, a customer's phone) is **LWW master data**. Result:
strong convergence with intuitive business semantics.

### 5. Transport (pluggable)

```
abstract class SyncTransport {
  Future<void> putBundle(String deviceId, String name, List<int> bytes);
  Future<List<BundleRef>> listBundles({required String sinceCursorJson});
  Future<List<int>> getBundle(BundleRef ref);
}
```

- **SharedFolderTransport** (default, serverless): reads/writes the configured
  shared directory. Works with any folder a cloud client already syncs, or a
  Windows network share, or a USB stick carried between counters.
- Future adapters (e.g. an object-store) can be added without touching the engine.

### 6. Sync engine loop

1. `export()` — flush local outbox to a bundle in our transport folder.
2. `import()` — pull peers' new bundles, apply via `SyncRegistry`, advance cursors.
3. `reproject()` — rebuild affected projections (inventory levels, balances).
4. Update `sync_meta` (last run, last hlc) and notify UI (status badge).

Runs: on app start, on a timer, on manual "Sync now", and (optionally) on a
file-watcher over the shared folder. Fully functional if it never runs — that's
the offline-first guarantee.

## Guarantees & tests

- **Convergence:** apply the same set of bundles in any order on two fresh DBs ⇒
  byte-identical projected state. (Property test in `test/sync/`.)
- **Idempotency:** re-importing a bundle changes nothing.
- **No lost stock/money:** N concurrent movements ⇒ on-hand = sum of all N.
- **Tombstone safety:** delete + concurrent late update ⇒ row stays deleted iff
  delete has the greater HLC.

## Conflict surfacing (UX)

LWW silently resolves most master-data conflicts. For *material* fields (e.g. a
price changed differently on two devices within the same window) the Sync screen
shows a reviewable log of overrides so a manager can audit/fix. Inventory & money
never need manual resolution because they're event-sourced.
