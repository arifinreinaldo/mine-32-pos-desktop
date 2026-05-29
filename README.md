# Mine32 POS

An **offline-first** Point of Sale for an **automotive spare-parts** retailer,
built with **Flutter** for **Windows desktop**. It works fully offline and shares
data across devices with a **serverless** sync engine — no backend to run.

Design benchmarks: **Xero** (double-entry accounting rigor) and **Shopify**
(commerce/inventory UX). Tax handling is ready for **Indonesia CoreTax** (PPN).

## Features

- **Catalog** — parts with variants, SKUs, barcodes, brands; automotive fitment
  (Year/Make/Model/Engine), cross-reference / interchange numbers, supersession,
  and a lookup that finds a part by SKU, barcode **or** any interchange number.
- **Inventory** — multi-location stock as an append-only movement ledger;
  on-hand is the sum of movements, so concurrent offline edits never lose stock.
- **Sell / Checkout** — keyboard- and barcode-scanner-friendly counter, cart,
  cash/card/transfer tender with change, and an 80mm **PDF receipt**.
- **Accounting** — double-entry general ledger, seeded chart of accounts,
  automatic revenue/PPN/COGS posting on every sale, trial balance.
- **Tax (Indonesia CoreTax)** — PPN (11%/12%) inclusive/exclusive, company
  NPWP + PKP status, per-sale DPP/PPN, buyer + faktur fields, **PPN CSV export**.
- **Reports** — date-filtered sales, revenue, DPP/PPN, sales-trend chart, top
  parts, trial balance.
- **Dashboard** — today's sales/revenue, low stock, recent sales.
- **Sync** — point every device at the same shared folder (OneDrive / Google
  Drive / Dropbox / network share); changes exchange as files. See `docs/SYNC.md`.

## Architecture

Clean, feature-first architecture with Riverpod (state/DI), Drift/SQLite
(reactive local DB, the source of truth), and go_router. Money is stored as
integer minor units; IDs are UUIDv7; every mutation is journalled to a change
log for sync. Full detail in [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md),
[`docs/DATA_MODEL.md`](docs/DATA_MODEL.md), [`docs/SYNC.md`](docs/SYNC.md) and
[`docs/TAX_INDONESIA.md`](docs/TAX_INDONESIA.md).

## Build & run (Windows)

Requires the Flutter SDK (stable) and Visual Studio with the "Desktop
development with C++" workload.

```powershell
flutter config --enable-windows-desktop
flutter pub get
dart run build_runner build          # generate Drift / JSON code
flutter run -d windows               # run in debug
flutter build windows --release      # build the .exe
```

The release build is in `build\windows\x64\runner\Release\`. The SQLite database
lives under `%APPDATA%\Mine32 POS\mine32.sqlite`.

## Multi-device sync (no server)

1. Put a shared folder on each PC (e.g. a synced OneDrive/Drive/Dropbox folder
   or a Windows network share).
2. On each PC: **Sync → Choose folder** → select that folder, then **Sync now**
   (or sync on a schedule). Devices exchange bundle files; data converges
   deterministically. It keeps working offline and syncs when the folder is
   reachable.

## Development

```bash
dart run build_runner build      # codegen (Drift + json_serializable)
flutter analyze                  # lints (must be clean)
flutter test                     # unit + widget tests
dart format .
# or run all gates:
bash scripts/check.sh
```

Conventions and the iteration backlog: [`CLAUDE.md`](CLAUDE.md),
[`docs/ROADMAP.md`](docs/ROADMAP.md).

> Note: Windows binaries are produced on Windows. CI here builds/tests on Linux
> as a compile proxy (the Dart/Flutter code is identical across desktop targets).
