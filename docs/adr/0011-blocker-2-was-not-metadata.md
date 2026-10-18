---
status: accepted
supersedes-part-of: ADR-0010
date: 2026-10-18
---

# 0011 — Blocker 2 was not a metadata problem, and the previous diagnosis was wrong

## The retraction

[ADR-0010](0010-unsafeflags-disable-testable.md) claimed, on the strength of one command:

> `TerminalKitCodecs.o` contains **zero** nominal type descriptors for `DecoderResult`.

**That was wrong, and the error was mine.** The command was

    nm TerminalKitCodecs.o | grep "nominal type descriptor"

`nm` prints **mangled** symbol names. There is no literal string `nominal type descriptor` in a
symbol table, so that grep could only ever return zero. It was a measurement that could not fail, and
it did not.

What the object actually contains:

    S _$s17TerminalKitCodecs13DecoderResultOMn      <- Mn IS the nominal type descriptor
    S _$s17TerminalKitCodecs13DecoderResultOMP      <- metadata pattern
    S _$s17TerminalKitCodecs13DecoderResultOWV      <- value witness table

`nm -g` shows all three are **exported**, and they are present in `libTerminalKitCodecs.a` too. The
metadata is there. `-emit-generic-metadata` was never the missing thing — and chasing it was chasing
a flag I had already shown does not exist.

## What the failure actually is

The symptom is real: a test target cannot `@testable import TerminalKitCodecs`.

**Plain import works.** A probe importing `TerminalKitCodecs` builds and links in release. So do all
four of this package's own test targets, which import `TerminalKitCore` and `TerminalKitTestSupport`.

**`@testable` is what fails.** And the difference is testability, not linkage: in a verbose build
`-enable-testing` appears for the test targets and for `TerminalKitRender` and `TerminalKitInput`, but
**not** for `TerminalKitCodecs`, `TerminalKitIO`, `TerminalKitStyle` or `TerminalKitText`. SwiftPM is
enabling it inconsistently, and the targets it skips are exactly the ones the imported tests need.

## What is ruled out, by probe

- **Not Aemi.** A scratch package with `@testable` against its own target passes **with** Aemi as a
  dependency and **without** it. Aemi's `unsafeFlags` are exonerated as the cause.
- **Not `unsafeFlags` in this package.** They are gone; the failure persists.
- **Not the descriptor, and not the archive.** Both verified present and exported.

ADR-0010's other finding stands and was separately confirmed: a target carrying `unsafeFlags` is not
built with `-enable-testing`. Those flags are still removed.

## What remains open, stated as open

Why SwiftPM enables testability for two library targets in this package and skips the other four. The
differences I can see between them are that the two that work are the ones whose sources came from
`KittyRenderer` and `KittyInput`, and the ones that fail came from `KittyCodecs`, `KittyTerminal` and
`KittyStyle` — which are the *older* moved modules. That is an observation, not an explanation.

**This is not solved.** It is recorded accurately, with the previous wrong answer retracted, because a
corrected wrong answer in a decision record is worth more than a missing one: anyone who reads ADR-0010
would otherwise start from "no metadata is emitted", which is false.

## Consequences

- Roadmap 0003's step 1 changes. Blocker 2 is not a missing-symbol problem to be fixed by adding a
  flag; it is an unexplained testability inconsistency, and it is still the gate on the Atelier move.
- The 3,096 lines of white-box tests inherited from Atelier still cannot be linked from this package
  yet. Nothing has been moved, and nothing has been lost.