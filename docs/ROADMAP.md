# Roadmap & Iteration Backlog — Mine32 POS

This is the **single source of truth for what to build next**. Work top-down.
Each task is a vertical slice that must end with all gates green (see CLAUDE.md),
a commit, and its checkbox ticked. Keep slices small enough to finish in one
iteration. When you finish a milestone, push.

Legend: `[ ]` todo · `[~]` in progress · `[x]` done

---

## M0 — Foundation & tooling
- [x] Flutter scaffold (Windows + Linux), green baseline, branch pushed
- [x] Project docs (VISION, ARCHITECTURE, DATA_MODEL, SYNC, ROADMAP, CLAUDE)
- [x] Dependencies added (riverpod, drift, go_router, uuid, intl, decimal, pdf, etc.)
- [x] `scripts/check.sh` runs all gates; strict `analysis_options.yaml` (lints)
- [x] App shell: Material 3 theme, `window_manager` (title/min size), scrollable side-nav + go_router shell, placeholder screens for each section
- [x] `Money` value type + tests; `Hlc` type + tests; `Result`/`AppFailure`

## M1 — Database & sync core
- [x] `SyncableTable` base; `AppDatabase` with `company_settings`, `devices`, `change_log`, `applied_changes`, `sync_meta`
- [x] `HlcService` (persists last hlc); `DeviceIdentity` (stable device id)
- [x] `ChangeLogWriter` + `SyncRepository` base — transactional write+oplog
      (money stored as int minor units + mapped in repos; no Money/enum converters needed)
- [x] `SyncRegistry` + `SyncEngine` (export/import/reproject hook); `SyncTransport` iface + `SharedFolderTransport` + `InMemoryTransport`
- [x] Tests: HLC ordering, **convergence** & **idempotency** & **order-independence** & **tombstone-safety** round-trips (no-lost-stock property lands in M3 with event tables)

## M2 — Catalog (parts) [Shopify + auto]
- [x] Tables: products, product_variants, categories, brands (LIKE search; FTS is a later optimisation)
- [x] Domain + repository (CRUD via SyncRepository) + tests (CRUD, search, brand find-or-create, sync round-trip)
- [x] UI: catalog list (search/filter), part editor (sku, barcode, price, cost, core charge, brand, active)
- [x] Auto-parts data: vehicles (YMME), fitments, cross_references, supersessions + repository + number-lookup + tests
- [ ] Auto-parts UI: fitment/cross-ref editor on the part screen
- [ ] Seed/import: CSV import of parts; sample data seeder
- [ ] Multi-variant editing (a product with several variants)

## M3 — Inventory [Shopify multi-location]
- [x] Tables: locations (M), stock_movements (E, append-only ledger)
- [x] On-hand via SUM-of-movements projection (computed; conflict-free, no reproject needed)
- [x] UI: stock list (search) + count-style adjust dialog (pick location, set new count)
- [x] Tests: on-hand/adjustTo correctness + **NO-LOST-STOCK** concurrent-movement convergence + location replication
- [ ] bins, stock_counts session, transfers, committed/incoming quantities + UI
- [ ] Materialised inventory_levels projection (perf optimisation at scale)

## M4 — Sales / Checkout [Shopify POS]
- [x] Tables: sales, sale_lines, payments (completed sales = immutable events)
- [x] Cart controller: add by search/scan, qty, totals (line discount in model)
- [x] Checkout: tender (cash/card/transfer), change; Sell screen (search+cart)
- [x] Posting: emit stock_movements on complete (deducts stock atomically)
- [x] Barcode (keyboard-wedge): search + Enter adds first match
- [x] Tests: cart math/controller, completeSale persist+stock+sync round-trip,
      full Sell-flow widget test (search→add→charge→complete)
- [ ] Accounting journals on complete (lands in M5)
- [ ] Receipt: PDF + print; returns/refunds; park/recall; void; line-discount UI

## M5 — Accounting [Xero]
- [ ] Tables: accounts (seeded COA), tax_rates, journals (E), journal_lines (E), account_balances (P)
- [ ] Posting engine + balanced-journal invariant; tax calculation
- [ ] UI: chart of accounts, journal browser, manual journal, tax rates
- [ ] Reports: Trial Balance, P&L, Balance Sheet, Tax summary (with date filters)
- [ ] Tests: posting rules (cash/credit sale, payment, receipt, adjustment), balances

## M6 — Customers & Purchasing
- [ ] customers + customer_vehicles; AR balance; credit limit; price tiers
- [ ] suppliers, purchase_orders, goods_receipts; AP; receiving emits stock+journals
- [ ] UI + tests for both

## M7 — Sync UX & Dashboard
- [ ] Sync screen: status, transport config (pick shared folder), "Sync now", history, conflict/override audit log
- [ ] Background timer + folder watcher; status badge in shell
- [ ] Dashboard: today's sales, low stock, top parts, cash position (fl_chart)

## M8 — Polish & hardening
- [ ] Settings: company, currency/rounding, tax defaults, receipt header/footer, backup/restore (DB file copy + bundle export)
- [ ] Empty/error/loading states everywhere; global error presenter
- [ ] DB migration tests; performance pass (50k SKU search)
- [ ] README with screenshots/build instructions for Windows (`flutter build windows`)
- [ ] Optional: SQLCipher encryption flag; golden tests for receipts

---

## Working agreement (Ralph loop)
- Always pick the **topmost unchecked** task. If it's large, split it and do the
  first sub-slice, leaving the rest checked-out as new sub-items.
- Never break the gates. If red, fixing red is the only task.
- Keep `docs/` honest — update DATA_MODEL/SYNC if the design evolves.
- Commit per task; push at least once per milestone.
