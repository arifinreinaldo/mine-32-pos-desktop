# LLM Wiki — Mine32 POS

> **Read this first.** A map of the codebase for any LLM/agent (and humans in a
> hurry). It indexes *where things live*, *what must not break*, and *how to add
> things*. For rules of engagement and the validation gates, see
> [`CLAUDE.md`](../CLAUDE.md). For deeper design, follow the links in
> [§12 Deep docs](#12-deep-docs).

---

## 1. What this is (30-second orientation)

**Mine32 POS** — an **offline-first**, **serverless** Point of Sale desktop app
for an **automotive spare-parts** retailer. Flutter, targeting **Windows
desktop** (Linux only for CI/dev compile + tests).

- **No backend.** Each device's local SQLite DB is the source of truth. Devices
  converge by exchanging **change bundles** through a shared/cloud folder
  (serverless sync). See [`docs/SYNC.md`](SYNC.md).
- **Benchmarks:** Xero (double-entry accounting rigor) + Shopify (commerce /
  inventory UX). Automotive-specific: vehicle fitment (YMME), interchange /
  cross-reference numbers.
- **Indonesia tax-ready:** PPN (VAT), DPP/PPN split, faktur fields, CoreTax CSV
  + XML export. See [`docs/TAX_INDONESIA.md`](TAX_INDONESIA.md).

## 2. Tech stack & gates

Flutter 3.44 / Dart 3.12. **Riverpod 3** (classic `Notifier`/`Provider` API — no
codegen), **Drift** over SQLite (codegen via `drift_dev`), **go_router**,
`json_serializable` for sync DTOs. Freezed and riverpod_generator are
deliberately **not** used.

Every task ends GREEN through these gates (run `./scripts/check.sh`):

```bash
export PATH="$PATH:/opt/flutter/bin"      # PATH is not persisted; prefix shells
dart run build_runner build               # 1. codegen (Drift + json) — no errors
flutter analyze                           # 2. "No issues found"
flutter test                              # 3. all pass
dart format --set-exit-if-changed .       # 4. already formatted
```

## 3. Repo map (layered, feature-first)

```
lib/
  main.dart                  # DI bootstrap, window, installs AppErrorReporter, starts SyncScheduler
  app/                       # app.dart (MaterialApp.router + global error listener), router.dart, theme/
  core/                      # cross-cutting; NO feature imports
    money/        money.dart            # Money value type (integer minor units)
    time/         hlc.dart, clock.dart  # Hybrid Logical Clock, injectable Clock
    result/       result.dart, app_failure.dart
    errors/       app_error_reporter.dart   # uncaught errors → snackbar
    backup/       backup_service.dart        # full JSON snapshot export/merge-restore
    database/     app_database.dart (schemaVersion), sync_repository.dart, syncable_table.dart, tables/
    sync/         hlc_service, change_log_writer, change_record, sync_entity (registry),
                  sync_engine, core_sync_entities, device_identity, transport/
    di/           app_services.dart (eager singletons), providers.dart (root providers)
  features/<feature>/{data,domain,presentation}
  shared/         formatters/ (money_format), widgets/ (app_shell, section_placeholder)
```

**Layer rules:** domain has **no Flutter/Drift imports**; presentation talks to
domain via Riverpod controllers; data implements repositories. All writes go
through a repository that updates Drift **and** appends to the change-log.

## 4. Feature catalog

Each feature lives in `lib/features/<feature>/`. Route + nav label are in
`lib/app/navigation.dart` / `router.dart`. Repositories extend `SyncRepository`.

| Feature | Route | Screens / dialogs | Repository (data/) | Key domain types |
|---|---|---|---|---|
| **dashboard** | `/dashboard` | dashboard_screen | (reads via providers) | — |
| **sales / checkout** | `/sell` | sell_screen (cart line-discount, park/recall), payment_dialog | sales_repository (`completeSale`) | cart (`Cart`/`CartLine`), `SaleResult`, `ParkedSale` |
| **sales history** | `/sales` | sales_history_screen, return_dialog | returns_repository (`createReturn`,`voidSale`) | receipt, `ReturnableLine` |
| **catalog** | `/catalog` | catalog_screen, part_editor_dialog (multi-variant), fitment_editor_dialog | catalog_repository (`savePart`,`itemsForProduct`), auto_parts_repository, parts_csv_import | `PartDraft` (`variantName`), `CatalogItem`, auto_parts_models (`VehicleDraft`) |
| **inventory** | `/inventory` | inventory_screen (incoming col), stock_adjust_dialog, stock_transfer_dialog, stock_count_dialog | inventory_repository (`addMovement`,`transfer`,`applyCount`,`onHand`,`stockAtLocation`) | stock_models (`StockLevel`,`LocationDraft`), `MovementReason` |
| **purchasing** | `/purchasing` | purchasing_screen, po_create_dialog, supplier_editor_dialog | purchasing_repository (`receivePurchaseOrder`,`paySupplier`,`watchIncomingByVariant`) | purchasing_models (`SupplierDraft`) |
| **customers** | `/customers` | customers_screen, customer_editor_dialog, customer_vehicle_dialog | customers_repository (`receivePayment`,`arBalance`) | `CustomerDraft` |
| **accounting** | `/accounting` | accounting_screen (3 tabs), manual_journal_dialog, tax_rate_editor_dialog | accounting_repository (`postJournal`,`postSaleJournal`…) | accounting_models (`AccountCode`,`JournalLineInput`), tax_math, coretax_csv, coretax_xml |
| **reports** | `/reports` | reports_screen (PPN CSV + CoreTax XML) | reports_repository | (P&L / Balance Sheet / PPN via accounting) |
| **sync** | `/sync` | sync_screen (history) | sync_service, sync_scheduler | `SyncInfo`, `SyncRun` |
| **settings** | `/settings` | settings_screen | settings_repository, sample_data | `SettingsDraft` |

Riverpod providers per feature live in `presentation/<feature>_controller.dart`
(e.g. `catalogRepositoryProvider`, `cartProvider`, `accountingRepositoryProvider`).
Root/cross-cutting providers are in `lib/core/di/providers.dart`
(`appServicesProvider`, `databaseProvider`, `moneyFormatProvider`,
`currencyScaleProvider`, `backupServiceProvider`, `pendingChangesProvider`,
`errorReporterProvider`).

## 5. Core subsystems

- **Money** (`core/money/money.dart`): integer **minor units**, never doubles.
  `Money.fromMajor("12.50", scale: 2)` → `Money(1250)`. Tax math uses `Decimal`
  intermediates then converts. Format via `moneyFormatProvider`
  (`currencyScaleProvider` gives scale: IDR=0, USD=2).
- **Database** (`core/database/`): one `AppDatabase` (`@DriftDatabase`),
  `schemaVersion` currently **10**. Tables split under `tables/` by concern.
  `SyncRepository.writeSyncable` stamps HLC + writes row + change-log atomically.
- **Sync** (`core/sync/`): every mutation appends a `ChangeRecord` to
  `change_log` (the outbox). `SyncEngine.export()` flushes unexported records to
  a bundle; `import()` merges peers' bundles idempotently (dedup via
  `applied_changes`) and only advances a peer cursor through a *contiguous*
  fully-applied prefix. `SyncRegistry` maps table name → `SyncEntity` (master =
  HLC last-write-wins, event = set-union). `SyncScheduler` runs it every 5 min.
- **DI** (`core/di/app_services.dart`): `AppServices.initialize()` opens the DB,
  loads HLC/device id, registers all sync entities, and seeds the chart of
  accounts + default PPN rate + company settings (idempotent). Injected via
  `appServicesProvider` (overridden in `main()`/tests).
- **Errors** (`core/errors/app_error_reporter.dart`): `main()` routes
  `FlutterError.onError` + `PlatformDispatcher.onError` here → snackbar.
- **Backup** (`core/backup/backup_service.dart`): JSON snapshot of every
  registered syncable table; restore merges via each entity's conflict rules.

## 6. Domain glossary

| Term | Meaning |
|---|---|
| **HLC** | Hybrid Logical Clock — `<wallMs>:<counter>:<deviceId>`; total order across devices without a server. Drives master last-write-wins. |
| **Change-log / oplog** | Append-only outbox (`change_log`); the unit of sync is a `ChangeRecord`. |
| **Master vs Event** | Master data = mutable, LWW by HLC, deletes = tombstones. Event data = append-only, union-merged (sales, stock_movements, journals, returns). Projections (on-hand, balances) are computed from events, never stored. |
| **DPP** | *Dasar Pengenaan Pajak* — VAT tax base (`sales.subtotalMinor`). |
| **PPN** | Indonesian VAT/output tax (`sales.taxTotalMinor`); default 11%. |
| **Faktur** | Indonesian tax invoice; buyer NPWP + serial captured per sale; exported as CoreTax CSV/XML. |
| **NPWP / PKP** | Tax id / VAT-registered status (company + buyer). |
| **Core charge** | Refundable deposit on a rebuildable part (`coreChargeMinor`). |
| **On-account sale** | Credit sale: `paidTotalMinor=0`, journal debits Accounts Receivable. |
| **Tax-inclusive** | Listed price already contains PPN (ID retail default); `TaxMath.split` separates DPP/PPN. |
| **YMME / fitment** | Year-Make-Model-Engine vehicle a part fits. |
| **Interchange / cross-reference** | Alternate part numbers that resolve to the same variant. |

## 7. Invariants — do not break these

1. **Money is integer minor units.** Never `double` for money.
2. **IDs are client-generated UUID v7 strings.** Never rely on autoincrement for
   syncable data. Seeded master rows use **deterministic ids**
   (`account:<code>`, `taxrate:default`, `location:default`) so devices converge
   to one row instead of duplicating by code.
3. **Every syncable table** carries `id, created_at, updated_at, deleted_at,
   updated_hlc` (extend `SyncableTable`).
4. **All writes go through a repository** → Drift + change-log via
   `writeSyncable`. Never write a syncable table directly.
5. **Event/ledger rows are immutable once posted** (sales, stock_movements,
   journals/lines, returns). Adjust by appending a reversing/compensating event,
   never by editing.
6. **Journals must balance** (`postJournal` throws if debits ≠ credits). A sale
   and its return/void provably net the trial balance to zero.
7. **Projections are derived** (on-hand = Σ movements; balances = Σ journal
   lines). Never store/edit them.
8. **Domain layer imports no Flutter/Drift.**

## 8. Accounting posting rules

Account codes (`accounting_models.dart::AccountCode`): cash `1-1000`, bank
`1-1100`, receivable `1-1200`, ppnInput `1-1300`, inventory `1-1400`,
accountsPayable `2-2000`, ppnOutput `2-2100`, ownerEquity `3-3000`,
salesRevenue `4-4000`, cogs `5-5000`, inventoryAdjustment `5-9000`. (11 seeded.)

| Event | Journal (Dr / Cr) | Posted by |
|---|---|---|
| Sale (cash/bank) | Dr Cash/Bank (total) · Cr Revenue (DPP) · Cr PPN Output (PPN); Dr COGS · Cr Inventory | `postSaleJournal` |
| On-account sale | Dr **Receivable** instead of Cash | `postSaleJournal(method:'account')` |
| Return / void | reverse of the sale; Cr Cash/Bank refund | `postReturnJournal` |
| Goods receipt (PO) | Dr Inventory (net) · [Dr PPN Input (recoverable VAT, PKP only)] · Cr Accounts Payable (gross) | `postPurchaseJournal` |
| Customer receipt | Dr Cash/Bank · Cr Receivable | `postReceiptJournal` |
| Supplier payment | Dr Accounts Payable · Cr Cash/Bank | `postSupplierPaymentJournal` |
| Manual journal | user-entered, balanced | `postManualJournal` |

## 9. "Where do I change X?" recipes

- **Add a syncable entity** → see the checklist in [`CLAUDE.md`](../CLAUDE.md)
  (Drift table → `AppDatabase` + bump `schemaVersion` + migration step → domain
  + repository via `writeSyncable` → register in the feature's `*_sync.dart` →
  tests incl. a sync round-trip).
- **Add a screen/section** → screen in `presentation/`, route in
  `app/router.dart`, nav entry in `app/navigation.dart` (update the navigation
  smoke test's section map).
- **Add an accounting flow** → a `postXxxJournal` in `accounting_repository.dart`
  using `AccountCode`; assert the trial balance stays balanced.
- **Change tax behavior** → `accounting/domain/tax_math.dart` (+ `tax_rates`).
- **Add a report/export** → `reports/` or `accounting/domain/coretax_*.dart`;
  wire a button in `reports_screen.dart`.
- **Touch sync semantics** → `core/sync/`; keep `docs/SYNC.md` honest.

## 10. Schema & migrations

`schemaVersion` lives in `app_database.dart`; migrations are stepwise
`if (from < N)` blocks (createTable/addColumn). **Guard `addColumn` against the
version where the table was first created** (a v1→v4 upgrade once crashed because
a column added in v6 was re-added to a table created with the current schema).
`test/core/migration_test.dart` builds a hand-rolled v1 DB and runs the real
upgrade chain — extend it when you add tables/columns.

## 11. Testing conventions

- **Repository tests**: in-memory `NativeDatabase.memory()`; build repos
  directly; for sync, use `InMemoryFolder` + `SyncEngine` (see
  `inventory_repository_test.dart`, `catalog_repository_test.dart`).
- **Widget tests on stream screens**: use **bounded pumps**
  (`pump` + `pump(Duration)`), not `pumpAndSettle` (a spinner/snackbar never
  settles). Unmount (`pumpWidget(SizedBox.shrink())`) + `pump(500ms)` to flush
  Drift's stream-close timer.
- **Dialogs that need a one-shot list**: call a `Future` query (e.g.
  `inventory.listLocations()`, `catalog.list()`), **not** `watchX().first` —
  awaiting a Drift watch stream in a dialog `initState` hangs under widget-test
  fake async (this stalled the whole suite twice). Reactive *screens* still use
  the `watchX()` stream via a `StreamProvider`.
- **Deterministic time**: pass `MutableClock(...)` into `AppServices.initialize`.

## 12. Deep docs

- [`docs/VISION.md`](VISION.md) — product & scope
- [`docs/ARCHITECTURE.md`](ARCHITECTURE.md) — layering, packages, boundaries
- [`docs/DATA_MODEL.md`](DATA_MODEL.md) — every table, column, kind (M/E/P)
- [`docs/SYNC.md`](SYNC.md) — HLC, change-log, bundles, merge, convergence
- [`docs/TAX_INDONESIA.md`](TAX_INDONESIA.md) — PPN/DPP, faktur, CoreTax
- [`docs/ROADMAP.md`](ROADMAP.md) — single source of truth for what to build next
- [`CLAUDE.md`](../CLAUDE.md) — agent rules, gates, conventions, checklists
