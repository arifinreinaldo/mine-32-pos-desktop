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
- [ ] App shell: Material 3 theme, `window_manager` (title/min size), nav rail + go_router shell, placeholder screens for each section
- [x] `Money` value type + tests; `Hlc` type + tests; `Result`/`AppFailure`

## M1 — Database & sync core
- [ ] `SyncableTable` base; `AppDatabase` with `company_settings`, `devices`, `change_log`, `applied_changes`, `sync_meta`
- [ ] `HlcService` (persists last hlc); `DeviceIdentity` (stable device id)
- [ ] `ChangeLogWriter` — transactional write+oplog; converters (Money/enums/DateTime)
- [ ] `SyncRegistry` + `SyncEngine` (export/import/reproject); `SyncTransport` iface + `SharedFolderTransport`
- [ ] Tests: HLC ordering, change-log emission, **convergence** & **idempotency** round-trip, no-lost-stock property

## M2 — Catalog (parts) [Shopify + auto]
- [ ] Tables: products, product_variants, categories, brands (+ FTS search)
- [ ] Domain + repository (CRUD via ChangeLogWriter) + tests
- [ ] UI: catalog list (search/filter/paginate), product editor (variants, sku, barcode, price, cost, core charge)
- [ ] Seed/import: CSV import of parts; sample data seeder
- [ ] Auto-parts: vehicles (YMME), fitments, cross_references, supersessions + UI + tests

## M3 — Inventory [Shopify multi-location]
- [ ] Tables: locations, bins, stock_movements (E), inventory_levels (P), stock_counts, transfers
- [ ] Projection rebuild from movements; on-hand/available/committed
- [ ] UI: stock by location, adjustments, transfers, stock count session
- [ ] Tests: projection correctness, concurrent-movement convergence

## M4 — Sales / Checkout [Shopify POS]
- [ ] Tables: sales, sale_lines, payments (drafts M, posted E)
- [ ] Cart controller: add by search/scan, qty, line discount, tax, totals
- [ ] Checkout: tender (cash/card/transfer/store credit), change, park/recall, void
- [ ] Posting: emit stock_movements + accounting journals on complete
- [ ] Receipt: PDF + print (`pdf`/`printing`); receipt settings
- [ ] Returns/refunds (negative sale linked to original)
- [ ] Keyboard-first UX + barcode (keyboard-wedge) + shortcuts; widget tests

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
