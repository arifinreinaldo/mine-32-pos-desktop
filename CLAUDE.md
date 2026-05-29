# CLAUDE.md — Mine32 POS

Guidance for any agent (and humans) working in this repo. Read this first.

## What this is

**Mine32 POS** is an **offline-first** Point of Sale desktop application for an
**automotive spare-parts** retailer, built with **Flutter** and targeting
**Windows desktop** (primary). Linux is supported for local development and CI
smoke-testing. There is **NO backend server**: the app is fully functional
offline, and multi-device data sharing happens via a **serverless sync engine**
(change-log + portable sync bundles exchanged through a shared/cloud-synced
folder). See `docs/SYNC.md`.

Design benchmarks: **Xero** (accounting rigor — double-entry ledger, tax,
invoicing) and **Shopify** (commerce/inventory UX — products, variants, SKUs,
multi-location stock, clean POS checkout).

## Tech stack

- Flutter 3.44 / Dart 3.12 (stable)
- **Riverpod 3** (`flutter_riverpod`, **classic API — no codegen**) — state & DI
- **Drift** (`drift` + `drift_dev`) over SQLite — local DB, single source of truth
- **go_router** — declarative routing with a persistent navigation shell
- **Native Dart 3 sealed/immutable classes** for domain models/unions;
  **`json_serializable`** for sync DTOs/envelopes (freezed & riverpod codegen are
  intentionally NOT used — only `drift_dev` + `json_serializable` run under build_runner)
- **uuid** — primary keys (UUID v7) for collision-free multi-device sync
- `pdf` + `printing` — receipts & invoices; `fl_chart` — reports; `csv` — import/export
- `window_manager` — desktop window sizing/title

## Commands (run from repo root)

Flutter is installed at `/opt/flutter`. PATH is not persisted, so prefix shells:

```bash
export PATH="$PATH:/opt/flutter/bin"
```

| Task | Command |
|------|---------|
| Get deps | `flutter pub get` |
| **Codegen** (Drift + json_serializable) | `dart run build_runner build --delete-conflicting-outputs` |
| Watch codegen | `dart run build_runner watch --delete-conflicting-outputs` |
| **Analyze** (gate) | `flutter analyze` |
| **Test** (gate) | `flutter test` |
| Format | `dart format .` |
| Build smoke (Linux) | `flutter build linux --debug` |
| Run (Linux dev) | `flutter run -d linux` |

## Validation gates — every task must end GREEN

A task is **done** only when ALL of these pass (in order):

1. `dart run build_runner build --delete-conflicting-outputs` — no errors
2. `flutter analyze` — **No issues found**
3. `flutter test` — all pass
4. `dart format --set-exit-if-changed .` — already formatted

Then commit with a clear message and update `docs/ROADMAP.md` (check the box).
Use `./scripts/check.sh` to run all gates at once.

## Conventions (non-negotiable)

- **Clean architecture, feature-first.** `lib/features/<feature>/{data,domain,presentation}`.
  Cross-cutting code lives in `lib/core/**`; shared widgets in `lib/shared/**`.
- **Money is integer minor units** (e.g. cents) via the `Money` value type
  (`lib/core/money/`). Never use `double` for money. Use `Decimal` for
  intermediate tax math, then convert to minor units.
- **IDs are UUID v7 strings** generated client-side. Never rely on autoincrement
  for syncable data.
- **Every syncable table** carries `id`, `created_at`, `updated_at`,
  `deleted_at` (nullable tombstone), `updated_hlc` (last-write HLC).
- **Sync semantics by table kind** (see `docs/SYNC.md`):
  - *Master data* (products, customers, suppliers, prices, settings): mutable,
    conflict resolution = **HLC last-write-wins** at row level; deletes = tombstones.
  - *Event/ledger data* (stock movements, sales, payments, journal lines):
    **append-only & immutable once posted**; sync = set-union (conflict-free).
  - Derived quantities (on-hand stock, account balances) are **projections**
    rebuilt from event tables — never edited directly.
- **All writes go through repositories**, which (a) update Drift and (b) append
  to the `change_log`. Never write a syncable table outside its repository.
- Domain layer has **no Flutter/Drift imports**. Presentation talks to domain
  via Riverpod controllers. Data layer implements domain repository interfaces.
- Prefer pure functions + small classes; write a test alongside each unit of logic.

## Adding a syncable entity (checklist)

1. Define the Drift table in `lib/core/database/tables/` extending `SyncableTable`.
2. Add it to `AppDatabase`; bump `schemaVersion` + add a migration step.
3. Create domain entity + repository interface in the feature's `domain/`.
4. Implement repository in `data/` — route mutations through `ChangeLogWriter`.
5. Register it in `SyncRegistry` (table name → applier) so sync can merge it.
6. Add tests: repository CRUD, change-log emission, and a sync round-trip.

## Definition of Done (per ROADMAP task)

- Code + tests for the slice; gates green; ROADMAP box checked; committed.
- No `TODO`-only stubs left where a behavior was promised by the task.
