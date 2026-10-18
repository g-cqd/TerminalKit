---
status: accepted
date: 2026-10-18
---

# 0010 — `unsafeFlags` silently disables `@testable`, and the Atelier move is blocked on two hard limits

## The finding

This package carried `.unsafeFlags(["-Xfrontend", "-warn-long-*"])` from its first commit. They were
added for strictness and looked free.

They are not free. **A target carrying `unsafeFlags` is not built with `-enable-testing`, so
`@testable import` of that module fails** with

    unable to resolve Swift module dependency to a compatible module: 'TerminalKitCodecs'

Verified rather than inferred: with the flags present, `swift build --build-tests -v` contains no
`-enable-testing` anywhere. Remove them and it appears. `ask` carries the same two flags and is
therefore in the same position — harmless there only because ADR-0002 already bans `@testable` in
release builds, so nothing is lost. That is luck, not design.

**The flags are removed.** A warning threshold that quietly costs the ability to test the thing at
all is not strictness; it is a trade made without noticing it was a trade.

## The Atelier switchover: two hard blockers, both now measured

The attempt to make Atelier consume TerminalKit was started three times and abandoned each time. This
time the blockers were found rather than guessed, and both are structural:

**1. `@testable` cannot cross a SwiftPM package boundary.** SwiftPM does not build dependencies with
testability. Atelier has **107 files** that white-box import the moved modules, in four suites
totalling 37 files and 3,096 lines, plus `AtelierText`'s own suite. Those suites therefore cannot stay
in Atelier — they have to move to this package, where `@testable` works. That makes the move
substantially larger than "delete six directories", and it is the reason a half-done switchover would
have been worthless.

**2. The library emits no metadata for its public generics.** `TerminalKitCodecs.o` contains **zero**
nominal type descriptors for `DecoderResult`. A test target linking the product fails to link. The
documented remedy, `-emit-generic-metadata`, **does not exist in Swift 6.4** (verified:
`swiftc -frontend -help` lists only `-prespecialize-generic-metadata` and
`-disable-generic-metadata-prespecialization`). A minimal reproduction did not reproduce it, so the
cause is still unknown.

## What did work, and is worth keeping

**The re-export shim approach.** Replacing each moved module's body with a single
`@_exported public import` means Atelier's 278 importers and its public API need **no changes at
all** — verified: `Apps/KittyCode`, `Packages/AtelierCore` and `Apps/GitDiffViewer` all built in
release against shimmed modules. That is the shape the switchover should take once the test suites
can move.

The only source change required anywhere was two type renames — `KittyLogger` → `TerminalLogger` and
`KittySequences` → `EscapeSequences` — touching 14 files, 57 references.

## Consequences

- The `-warn-long-*` flags are gone from this package, with the reason recorded rather than just the
  removal.
- `ask` should make the same removal, on the same reasoning, rather than relying on a ban that happens
  to hide it.
- Roadmap 0003 is rewritten with the measured scope, the shim shape that works, and the two blockers.
  Nothing about this is a guess any more.