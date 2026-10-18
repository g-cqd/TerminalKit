---
status: done
blocked-by:
date: 2026-10-18
---

# 0003 — Atelier consumes TerminalKit instead of its own copies

TerminalKit holds the six modules. Atelier now consumes them through six compatibility
re-exports, and its duplicate implementations and owning suites are gone.

## Blocker 2 resolved

ADR-0012 and entry 0005 establish the missing setting:
`swift test -c release --enable-testable-imports` compiles, links and runs a codec regression
with `@testable import`. The previous metadata and `unsafeFlags` diagnoses are retracted.
Do not add metadata flags, resilience settings or public access to work around the old error.

## Owning-suite verification

56 existing test files were imported from Atelier `ba01419`: four terminal suites and
AtelierText's suite. Module imports, the two renamed symbols and generic support filenames
changed; assertions did not.

`swift test -c release --enable-testable-imports` exits 0. Seven targets report
153 + 2 + 74 + 35 + 17 + 26 + 61 = 368 tests. Opt-in performance benchmarks are skipped unless
explicitly requested. This is correctness validation, not a benchmark result.

## Consumer switch, verified

Atelier commit `f458d51`, pull request g-cqd/Atelier#4, branch `chore/consume-terminalkit`:

- Six implementation modules replaced by re-exports; 43 source files removed, 56 duplicate
  owning test files removed after their imported copies passed here.
- 46 app test files that inspect the implementation import the owning TerminalKit module and
  declare its product dependency. No production internals were made public.
- TerminalKit pinned at `7a1f22a` in KittyCode and AtelierCore; lockfiles gain only that pin.
- Results: KittyCode exit 0 with 970 tests in 8 targets; AtelierCore exit 0 with 1,628 tests in
  22 targets; GitDiffViewer exit 0 with 1,161 tests in 215 suites. The KittyCode binary runs.

A compatibility suite checks canonical type identity across the old and new module names, with a
negative control that restores the original local style implementation and observes the failure.

## Remaining

The six compatibility module names stay until callers migrate their imports. Removing them is a
source-breaking cleanup, deliberately not bundled into the switch. `ask` pins the same revision.

## Historical scope estimates — recheck before migration

Earlier probes reported 278 importers, 37 terminal test files / 3,096 lines, and 14 consumer
files using renamed types. They were not a complete dependency audit: 107 white-box importers
and 37 owning-suite files are different sets, and AtelierText has its own tests as well.
