---
status: not-started
blocked-by:
date: 2026-10-18
---

# 0003 — Atelier consumes TerminalKit instead of its own copies

TerminalKit now holds all six modules, but **Atelier still carries its own copies**. Until this entry
is done the code exists twice, which is the duplication the extraction was meant to remove.

## Measured scope

Probing, not estimating: **278 files** import the moved modules.

| Module | importers |
|---|---|
| `KittyCodecs` | 187 |
| `AtelierText` | 132 |
| `KittyRenderer` | 121 |
| `KittyTerminal` | 87 |
| `KittyInput` | 38 |
| `KittyStyle` | 27 |

## Why it is not done here

The attempt was started and **aborted**, deliberately. The import rewrite is mechanical and was
verified correct across all 278 files. The two `Package.swift` manifests were not: editing target
declarations and dependency arrays with a pattern rewrite corrupted them twice, producing a manifest
that no longer parsed. That is a sign the tool was wrong for the job, not that the plan was.

Atelier was restored to a clean, building state rather than left half-migrated. Its main branch
builds and its tests are untouched — a working repository is worth more than a broken one that is
nearly finished.

## The approach, for whoever takes it

1. Add the TerminalKit dependency to `Apps/KittyCode` and `Packages/AtelierCore`.
2. **Delete the six target declarations by hand.** They are multi-line blocks with comments; do not
   find them by pattern.
3. Rewrite every dependency array that names a moved module to
   `.product(name: "TerminalKit…", package: "TerminalKit")`. Explicit product references are required —
   the bare string form did not resolve for `ask` against TerminalKit.
4. Then, and only then, delete the six module directories and rewrite the imports.
5. Build all three packages and run their suites.

Steps 4 and 5 are the irreversible ones. Steps 1–3 can be done and verified — a manifest that parses
and resolves is worth having on its own, and it makes the delete reversible by a single `git revert`.
