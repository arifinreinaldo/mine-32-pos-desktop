# Architecture — Mine32 POS

**Primary platform: Windows desktop.** Linux builds exist only so CI/dev can run
`analyze` / `test` / `build` as a compile proxy (Windows binaries can't be built
on the Linux CI box). Nothing in `lib/**` is platform-specific beyond what the
plugins abstract.

## Layered, feature-first clean architecture

```
lib/
  main.dart                 # bootstraps DI + window, runs App
  app/
    app.dart                # MaterialApp.router, theme wiring
    router.dart             # go_router: shell route + feature routes
    theme/                  # Material 3 theme, colors, typography, spacing
  core/                     # cross-cutting, no feature deps
    money/                  # Money value type (integer minor units)
    time/                   # Hlc (hybrid logical clock), Clock
    result/                 # Result<T>/AppFailure types
    database/
      app_database.dart     # @DriftDatabase, migrations
      tables/               # Drift table defs (SyncableTable base)
      converters/           # type converters (Money, DateTime, enums)
    sync/                   # serverless sync engine (see docs/SYNC.md)
      change_log.dart       # ChangeLogWriter, change records
      hlc_service.dart
      sync_engine.dart      # export/import/merge orchestration
      transport/            # SyncTransport iface + SharedFolderTransport
      sync_registry.dart    # table -> applier mapping
    di/                     # Riverpod root providers (db, clock, deviceId...)
    utils/ , extensions/ , constants/
  features/<feature>/
    data/                   # DAOs, repository impls, mappers
    domain/                 # entities, value objects, repo interfaces, use cases
    presentation/           # Riverpod controllers (state) + screens + widgets
  shared/
    widgets/                # reusable UI (buttons, fields, data tables, empty states)
    formatters/             # money/date/number formatting
```

### Dependency rule

`presentation → domain ← data`. Domain depends on nothing app-specific (no
Flutter, no Drift). Data implements domain interfaces and is the only layer that
touches Drift + the change log. Presentation depends on domain abstractions,
resolved to data implementations via Riverpod providers in `core/di`.

## State management — Riverpod 3 (classic API, no codegen)

- Async/UI state via `Notifier`/`AsyncNotifier` + `NotifierProvider`.
- Repositories exposed as providers; the DB, clock, device id, and sync engine
  are root providers overridden in tests with fakes/in-memory DB.
- Reactive reads use Drift's `watch*` streams surfaced through providers, so the
  UI updates automatically when sync merges remote changes.

## Routing — go_router

- A `ShellRoute` renders the persistent `NavigationRail` + top bar; child routes
  swap the body: `/dashboard`, `/sell`, `/catalog`, `/inventory`, `/purchasing`,
  `/customers`, `/accounting`, `/reports`, `/sync`, `/settings`.
- Keyboard shortcuts (e.g. F2 = focus search, F9 = pay) are global via `Shortcuts`/`Actions`.

## Persistence — Drift / SQLite

- One `AppDatabase`. Tables split by file under `core/database/tables/`, DAOs per
  feature. Native SQLite via `sqlite3_flutter_libs` (ships the Windows DLL).
- DB file lives under `path_provider`'s app-support dir
  (`%APPDATA%/Mine32 POS/mine32.sqlite` on Windows).
- Schema migrations are explicit and tested; `schemaVersion` bumped per change.

## Money & numbers

- `Money` = `{ int minorUnits, String currency }`. All persisted amounts are
  integer minor units. Tax math uses `Decimal` then rounds to minor units with a
  documented rounding rule (half-up). Formatting via `intl`.

## Offline-first & sync (summary; full detail in docs/SYNC.md)

- Local DB is the **source of truth**; UI never awaits the network.
- Every repository mutation appends a `change_log` row (the outbox/oplog).
- A `SyncEngine` exports unsynced changes into a portable **bundle** and imports
  peers' bundles from a `SyncTransport` (default: a shared/cloud-synced folder).
- Merge is deterministic: master data = HLC last-write-wins; event tables =
  append-only union; deletes = tombstones; quantities/balances are projections.

## Error handling

- Domain returns `Result<T>` (`Ok`/`Err(AppFailure)`); no exceptions across
  layer boundaries for expected failures. Unexpected errors are logged and
  surfaced via a global error presenter.

## Testing strategy

- **Unit**: Money, Hlc, tax/posting rules, sync merge (property-style:
  out-of-order bundles converge), repositories against in-memory Drift.
- **Widget**: key screens (checkout flow, catalog list) with overridden providers.
- **Golden** (optional later): receipt/invoice layout.
- Gates: `build_runner` + `flutter analyze` + `flutter test` + `dart format`.

## Key decisions (ADR-style)

| # | Decision | Why |
|---|---|---|
| 1 | Drift over Isar/Hive | Type-safe SQL, reactive streams, migrations, mature on Windows |
| 2 | Serverless folder-sync over client/server | User requirement: offline-first, no server to run |
| 3 | HLC + LWW for master data; event-sourced stock/ledger | Deterministic, conflict-free convergence without a coordinator |
| 4 | Integer minor units + double-entry | Financial correctness (Xero benchmark) |
| 5 | UUID v7 PKs | Multi-device inserts never collide; time-sortable |
| 6 | Riverpod + go_router | Testable DI, desktop-friendly declarative nav |
