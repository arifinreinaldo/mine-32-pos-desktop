# Vision — Mine32 POS

## Problem

An automotive spare-parts retailer needs a fast, reliable Point of Sale that
works **even when the internet is down** (shops often have flaky connectivity),
runs on ordinary **Windows** PCs, and can **share data across counters/branches
without depending on a central server** the owner has to run and maintain.

## Product

A Windows desktop POS that combines:

- **Shopify-grade commerce/inventory**: products with variants, SKUs & barcodes,
  multi-location stock, real-time available/committed/on-hand quantities, stock
  counts, transfers, purchase orders & goods receipt.
- **Xero-grade accounting**: a proper double-entry general ledger, chart of
  accounts, tax handling, invoices/receipts, and core financial reports
  (P&L, Balance Sheet, Trial Balance, Tax summary).
- **Automotive-specific** capability: vehicle fitment (Year/Make/Model/Engine),
  part cross-reference / interchange, supersession chains, and core charges.

All of it **offline-first**, with **serverless multi-device sync**.

## Principles

1. **Offline is the default, not a fallback.** The local database is the source
   of truth. The UI never blocks on the network.
2. **No server to run.** Sync is peer-to-peer via portable change bundles
   exchanged through a shared/cloud-synced folder (OneDrive/Dropbox/LAN share).
3. **Money is sacred.** Integer minor units, double-entry accounting, immutable
   posted transactions, deterministic conflict resolution.
4. **Fast at the counter.** Keyboard-first checkout, barcode-scanner (keyboard
   wedge) friendly, sub-second search over tens of thousands of parts.
5. **Auditable.** Every stock and money change is an append-only event you can
   trace; nothing is silently overwritten.

## Primary users

- **Cashier / counter staff** — search parts, build a sale, take payment, print.
- **Parts specialist** — look up fitment, cross-reference, supersession, cores.
- **Store manager / owner** — inventory, purchasing, pricing, reports, accounts.

## Benchmark mapping

| Capability | Benchmark | Where in Mine32 |
|---|---|---|
| Double-entry ledger, COA, tax, invoicing | Xero | `features/accounting`, `features/sales` |
| Inventory valuation, COGS on sale | Xero | `accounting` posting rules |
| Products, variants, SKUs, barcodes | Shopify | `features/catalog` |
| Multi-location stock; on-hand/committed/available | Shopify | `features/inventory` |
| Stock counts, transfers, adjustments | Shopify | `features/inventory` |
| Clean, fast POS checkout & receipts | Shopify POS | `features/sales` |
| Fitment (YMME), cross-ref, supersession, cores | Auto-parts ERP | `features/catalog` |

## Out of scope (initially)

- A hosted backend / web storefront / payment-gateway integration.
- Online VIN-decode databases (structure supports fitment; data is user-entered/imported).
- Mobile/tablet form factors (desktop-first; code stays portable).

## Non-functional targets

- Cold start < 2s; part search results < 200ms at 50k SKUs.
- Zero data loss across crashes and concurrent multi-device edits.
- Deterministic sync: same bundles applied in any order converge to same state.
