# Ralph Loop Prompt — Mine32 POS

You are iterating on **Mine32 POS**, an offline-first Windows desktop POS for
automotive spare parts (no backend server; serverless folder-sync). This prompt
runs repeatedly; each run makes ONE coherent, shippable increment.

## Each iteration, do exactly this:

1. **Orient.** Read `CLAUDE.md`, `docs/ROADMAP.md`, and the relevant `docs/*`.
   Run `bash scripts/check.sh`. If it's RED, your only task is to make it GREEN.

2. **Pick one task.** Choose the **topmost unchecked** item in `docs/ROADMAP.md`.
   If it's too big for one iteration, split it into sub-items and do just the
   first sub-slice. Mark it `[~]` while working.

3. **Implement the vertical slice** following the conventions in `CLAUDE.md` and
   the design in `docs/ARCHITECTURE.md` / `DATA_MODEL.md` / `SYNC.md`:
   - Tables extend `SyncableTable`; mutations go through repositories +
     `ChangeLogWriter`; respect M/E/P sync semantics.
   - Money = integer minor units; IDs = UUID v7; domain layer stays Flutter-free.
   - Write tests alongside the code (unit for logic, widget for screens, and a
     sync round-trip when you add a syncable entity).

4. **Make it GREEN.** Run, in order, until all pass:
   - `dart run build_runner build --delete-conflicting-outputs`
   - `flutter analyze`  → No issues found
   - `flutter test`     → all pass
   - `dart format .`
   (or just `bash scripts/check.sh`)

5. **Record & commit.** Tick the checkbox in `docs/ROADMAP.md` (and add any new
   sub-items you discovered). Commit with a clear, scoped message. Push at least
   once per milestone (`git push -u origin claude/great-ptolemy-B1JZW`).

## Rules
- Never leave the tree red or the build broken between commits.
- No fake "done": if the task promised a behavior, implement it (no stub-only).
- Prefer finishing/strengthening an existing slice over starting many shallow ones.
- Keep the docs honest — update DATA_MODEL/SYNC if the design changes.
- Small, frequent commits beat giant ones.

## Environment
- `export PATH="$PATH:/opt/flutter/bin"` at the start of every shell.
- Target is **Windows**; Linux is only a compile/test proxy (can't emit .exe here).
- Work on branch `claude/great-ptolemy-B1JZW`.
