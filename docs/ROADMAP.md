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
- [x] Auto-parts UI: fitment/cross-ref editor on the part screen (vehicle picker w/ dedupe; add/remove fitment + interchange)
- [x] Sample data seeder (Settings → Load sample data: 10 parts + stock + supplier + customer + fitment)
- [x] Seed/import: CSV import of parts (header-aliased, upsert-by-SKU, scale-aware, per-line errors; template + Settings UI)
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
- [x] Accounting journals on complete (lands in M5)
- [x] Sales history screen ("Sales" section: list + master-detail with lines/totals + reprint receipt)
- [x] Returns/refunds: event tables (v10), restock + reversing revenue/PPN/COGS journal, over-return guard, dialog on the sale detail
- [ ] park/recall; void; line-discount UI

## M5 — Accounting + Tax (Xero rigor; Indonesia CoreTax) + Reporting
- [x] Tables: accounts (seeded COA), tax_rates, journals (E), journal_lines (E); balances via trial balance
- [x] Posting engine + balanced-journal invariant; integer PPN tax math (inclusive/exclusive, DPP/PPN)
- [x] CoreTax-ready data: company NPWP + PKP flag + tax-inclusive setting; per-sale DPP/PPN + buyer name/NPWP + faktur number
- [x] Sale completion posts the revenue/PPN/COGS journal automatically
- [x] UI: Accounting screen (chart of accounts + balances); Reports screen (range filter, stat cards, fl_chart sales trend, top parts, trial balance, PPN summary)
- [x] Tests: tax math, balanced posting, sale→journal, PPN tax summary, reports & accounting screens
- [x] CoreTax PPN CSV export (Reports → "PPN CSV"; faktur rows with DPP/PPN/buyer/NPWP)
- [x] P&L + Balance Sheet statements (Reports screen, period-filtered)
- [x] Journal browser (Accounting → Journals tab: list + expandable legs) + manual journal entry (balanced-only Post)
- [x] Tax-rate editor (Accounting → Tax rates tab: CRUD, single-default invariant, inclusive/exclusive, % entry)
- [ ] CoreTax XML faktur

## M6 — Customers & Purchasing
- [x] customers + customer_vehicles; AR balance (watch); credit limit
- [x] On-account (credit) sales: paid=0, journal debits Accounts Receivable
- [x] Customers UI (master-detail: info, AR, vehicles, purchase history) + checkout customer picker + Account tender
- [x] Tests: customer CRUD/search/vehicles/sync + on-account→AR + balanced journal
- [x] suppliers + purchase_orders + lines; create PO; **receive → +stock + Dr Inventory / Cr AP journal**; AP balance; idempotent receive
- [x] Purchasing UI (tabbed: suppliers list/editor + POs list with New-PO dialog + Receive) + tests
- [x] Settle AR (customer receipts) + AP (supplier payments): event-sourced ledger + balanced journals (Dr Cash/Cr AR; Dr AP/Cr Cash) + UI (Receive payment / Pay)
- [ ] price tiers; partial receipts; input-PPN on purchases; receipt allocation per invoice

## M7 — Sync UX & Dashboard
- [x] Sync screen: device id, pick shared folder (file_picker), pending-changes count, last-sync, "Sync now" running the folder-transport engine
- [x] SyncService + controller; **real shared-folder round-trip test** (replicates via files, no server)
- [x] Dashboard: today's sales + revenue, low-stock count/list, parts count, recent sales
- [ ] Background timer + folder watcher; sync status badge in the shell; sync history / conflict-override audit log

## M8 — Polish & hardening
- [x] Settings screen: company profile, currency (USD/IDR/… → reactive money format), NPWP + PKP, tax-inclusive, receipt header/footer
- [x] CoreTax PPN CSV export
- [x] PDF receipt (80mm) + print via `printing`; "Print" action after a sale
- [x] README with Windows build instructions (`flutter build windows`)
- [x] Backup/restore (full JSON snapshot of all syncable tables; merge-restore via entity conflict rules; Settings UI) — also fixed latent duplicate-on-sync of seeded accounts/locations via deterministic seed ids
- [ ] Global error presenter
- [x] DB migration test (v1 -> current upgrade chain, data preserved) [caught + fixed a real upgrade crash]
- [ ] performance pass (50k SKU search)
- [ ] Optional: SQLCipher encryption; golden tests for receipts

---

## Working agreement (Ralph loop)
- Always pick the **topmost unchecked** task. If it's large, split it and do the
  first sub-slice, leaving the rest checked-out as new sub-items.
- Never break the gates. If red, fixing red is the only task.
- Keep `docs/` honest — update DATA_MODEL/SYNC if the design evolves.
- Commit per task; push at least once per milestone.
