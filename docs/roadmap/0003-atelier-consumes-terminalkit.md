---
status: not-started
blocked-by:
date: 2026-10-18
---

# 0003 — Atelier consumes TerminalKit instead of its own copies

TerminalKit holds all six modules; **Atelier still carries its own copies**, so the duplication the
extraction was meant to remove still exists. ADR-0010 records the attempt, the two structural blockers
found, and the one approach that verifiably works.

## Measured scope

| | |
|---|---|
| Files importing the moved modules | **278** |
| Files white-box importing them (`@testable`) | **107**, in 37 files / 3,096 lines |
| Type renames required across Atelier | 14 files, 57 references |

## Two hard blockers, both measured

**1. `@testable` cannot cross a SwiftPM package boundary.** SwiftPM does not build dependencies with
testability, so the 107 white-box files cannot stay in Atelier. Those suites must move here. This is
why the switchover is not "delete six directories".

**2. Unexplained testability inconsistency — UNSOLVED.** A test target cannot `@testable import`
`TerminalKitCodecs`, though a plain import of the same module builds and links in release. In a verbose
build `-enable-testing` is passed to the test targets and to `TerminalKitRender`/`TerminalKitInput`,
but not to `TerminalKitCodecs`, `TerminalKitIO`, `TerminalKitStyle` or `TerminalKitText`. Aemi is
ruled out as the cause by probe; this package's `unsafeFlags` are gone and it persists.

An earlier version of this entry blamed missing metadata. **That was wrong** and is retracted in
ADR-0011: the descriptor is present and exported, and the original grep could not have found it
because `nm` prints mangled names.

**Blocker 2 must be solved first** — without it the moved suites cannot build here.

## The approach, in order

1. **Solve blocker 2.** Nothing below works until a test target can link `TerminalKitCodecs`.
2. **Move the four suites here**: `TerminalKitIOTests`, `TerminalKitCodecsTests`,
   `TerminalKitInputTests`, `TerminalKitRenderTests`, plus `AtelierText`'s. Verified to import nothing
   outside the moved modules, so they move cleanly.
3. **Replace each Atelier module body with a shim** — one file, `@_exported public import`. Verified:
   `Apps/KittyCode`, `Packages/AtelierCore` and `Apps/GitDiffViewer` all build in release this way,
   with **zero changes to the 278 importers** and no change to Atelier's public API.
4. Apply the two type renames (`KittyLogger` → `TerminalLogger`, `KittySequences` → `EscapeSequences`)
   — 14 files, already scoped.
5. Add the TerminalKit dependency to `Apps/KittyCode` and `Packages/AtelierCore`; point each shim
   target at the product that owns the code.
6. Run all three suites.

Steps 3–5 are reversible by a single revert. Step 1 is not a step at all; it is the thing that has to
be solved first, and nothing about it is guessed — the absence of the symbols was measured with `nm`.