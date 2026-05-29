# Data Model — Mine32 POS

All syncable tables extend a common base:

```
SyncableTable:
  id           TEXT PK     -- UUID v7, client-generated
  created_at   INTEGER     -- epoch ms (UTC)
  updated_at   INTEGER     -- epoch ms (UTC)
  deleted_at   INTEGER?    -- tombstone (soft delete); NULL = live
  updated_hlc  TEXT        -- HLC of last write (for LWW)
```

Table kinds (drives sync semantics — see `docs/SYNC.md`):
- **M = master/mutable** (LWW)  **E = event/append-only** (union)  **P = projection** (derived)

## Catalog (Shopify + auto-parts)

- **products** (M): sku_root, name, description, brand_id→brands, category_id→categories,
  unit (each/set/litre), is_active, has_variants, default tax_rate_id, attributes(json).
- **product_variants** (M): product_id→products, sku, barcode, name (e.g. "OEM",
  "Aftermarket"), price (minor units), cost (minor units), core_charge (minor units?),
  weight_g, is_active. Every product has ≥1 variant (default).
- **categories** (M): name, parent_id→categories (tree).
- **brands** (M): name, manufacturer code.
- **price_tiers** (M) + **variant_prices** (M): tiered/wholesale pricing per variant.
- Automotive:
  - **vehicles** (M): make, model, year_from, year_to, engine, body. (YMME)
  - **fitments** (M): variant_id→product_variants, vehicle_id→vehicles, note. (M:N)
  - **cross_references** (M): variant_id, other_number, other_brand, type(OEM/interchange).
  - **supersessions** (M): old_variant_id, new_variant_id, reason, date.

## Inventory (Shopify multi-location)

- **locations** (M): name, type(store/warehouse), address, is_default.
- **bins** (M): location_id→locations, code (shelf/rack).
- **stock_movements** (E): variant_id, location_id, bin_id?, qty (signed),
  reason(sale/purchase/adjustment/transfer_in/transfer_out/return/count),
  ref_type, ref_id, unit_cost (for valuation), hlc. **Append-only.**
- **inventory_levels** (P): variant_id+location_id → on_hand, committed, incoming.
  Derived: `on_hand = Σ stock_movements.qty`; `available = on_hand - committed`.
- **stock_counts** (M header) + **stock_count_lines** (E): physical count sessions;
  posting a count emits adjustment movements.
- **transfers** (M header) + **transfer_lines**: between locations (emit movements).

## Sales (Shopify POS + Xero invoicing)

- **sales** (E once posted): number, customer_id?, location_id, status(draft/parked/
  completed/refunded/voided), subtotal, tax_total, total, paid_total, hlc, posted_at.
  Drafts are M; once **completed** the row + lines are immutable (E).
- **sale_lines** (E): sale_id, variant_id, description, qty, unit_price, discount,
  tax_rate_id, tax_amount, line_total, unit_cost(for COGS), core_charge.
- **payments** (E): sale_id, method(cash/card/transfer/store_credit), amount,
  tendered, change, reference.
- **returns/refunds**: modeled as sales with negative quantities linked via
  original_sale_id (keeps ledger append-only).

## Customers

- **customers** (M): name, phone, email, tax_number, address, credit_limit,
  price_tier_id?, balance(P from ledger), notes.
- **customer_vehicles** (M): customer_id, vehicle_id?, plate, vin, notes.

## Purchasing

- **suppliers** (M): name, contact, terms, tax_number, address.
- **purchase_orders** (M header): supplier_id, status(draft/ordered/partial/received/
  cancelled), expected_at, totals.
- **purchase_order_lines** (M/E): po_id, variant_id, qty_ordered, qty_received, unit_cost.
- **goods_receipts** (E) + lines: receiving against a PO emits +stock_movements and
  posts inventory/AP journals.

## Accounting (Xero double-entry)

- **accounts** (M): code, name, type(asset/liability/equity/income/expense),
  subtype, is_active, tax_rate_id?. Chart of Accounts (seeded defaults).
- **tax_rates** (M): name, percent (basis points), components(json), is_active.
- **journals** (E): date, source(sale/purchase/payment/adjustment/manual),
  ref_type, ref_id, memo, posted (bool). **Immutable once posted.**
- **journal_lines** (E): journal_id, account_id, debit(minor), credit(minor),
  tax_rate_id?, description. Σ debit == Σ credit (enforced).
- **account_balances** (P): account_id → balance, derived from journal_lines.

### Posting rules (examples)

- **Cash sale**: Dr Cash `total`; Cr Sales Revenue `subtotal`; Cr Tax Payable
  `tax_total`. Plus COGS: Dr COGS `Σ unit_cost·qty`; Cr Inventory same.
- **Credit sale**: Dr Accounts Receivable instead of Cash.
- **Customer payment**: Dr Cash/Bank; Cr Accounts Receivable.
- **Goods receipt**: Dr Inventory; Cr Accounts Payable (+ tax handling).
- **Stock adjustment (write-off)**: Dr Inventory Shrinkage; Cr Inventory.

## Settings / sync infra

- **company_settings** (M): name, address, tax_number, currency, rounding,
  receipt_header/footer, logo.
- **devices** (M): device_id, name, last_seen_hlc.
- **change_log** (local, not synced as data — it *is* the sync payload): id,
  table_name, row_id, op(upsert/delete), payload(json snapshot), hlc, device_id,
  exported(bool).
- **applied_changes** (local): change_id PK, applied_at — idempotency/dedupe.
- **sync_meta** (local): key/value (last export hlc, peer cursors, transport cfg).

## Indexing (performance)

- `product_variants(sku)`, `product_variants(barcode)` unique; FTS index over
  product name/sku/description for fast counter search.
- `stock_movements(variant_id, location_id)`, `journal_lines(account_id)`,
  `change_log(exported)`, `sale_lines(sale_id)`.
