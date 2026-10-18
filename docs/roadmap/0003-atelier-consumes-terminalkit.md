---
status: not-started
blocked-by:
date: 2026-10-18
---

# 0003 — Atelier consumes TerminalKit instead of its own copies

TerminalKit holds the six modules; Atelier still carries its implementations. Replace them only
once their inherited suites pass here and the consumers build against the shared code.

## Blocker 2 resolved

ADR-0012 and entry 0005 establish the missing setting:
`swift test -c release --enable-testable-imports` compiles, links and runs a codec regression
with `@testable import`. The previous metadata and `unsafeFlags` diagnoses are retracted.
Do not add metadata flags, resilience settings or public access to work around the old error.

## Next steps

1. Import the four terminal suites and AtelierText's suite, declaring each imported target in
   the test target's dependencies. Preserve assertions while adapting imports and type renames.
2. Run optimized tests with explicit testability. Prefer owning-module tests for internals;
   cross-package testability must be probed, not assumed impossible.
3. Replace Atelier's implementation directories with re-export shims, preserving module names
   and public APIs. The prior consumer-build experiment succeeded with this shape.
4. Apply `KittyLogger` → `TerminalLogger` and `KittySequences` → `EscapeSequences` to consumers.
5. Pin TerminalKit in the manifests and run each affected package's tests/builds.
6. Remove duplicate owning suites from Atelier only once their assertions are verified here.

## Historical scope estimates — recheck before migration

Earlier probes reported 278 importers, 37 terminal test files / 3,096 lines, and 14 consumer
files using renamed types. They were not a complete dependency audit: 107 white-box importers
and 37 owning-suite files are different sets, and AtelierText has its own tests as well.

Atelier is currently clean at `ba01419`. No partial source deletion is staged there.
