---
status: not-started
blocked-by:
date: 2026-10-18
---

# 0004 — Guard the hot path's allocations

The runtime principle says fewest allocations, with ceilings that are measured rather than
described. `ProcessFootprint` is committed and **tested in both directions** — it must report zero for
work that allocates nothing and must report growth for work that demonstrably allocates, because a
blind instrument would pass every ceiling in the project by reporting nothing.

## What is blocked, and on what

The guard on a real hot path is **not** written, for two measured reasons.

**1. Aemi's `expectAllocations` is now reachable** — exporting `CAemiKernels` and
`CAemiTestKitMalloc` as products fixed the resolution failure, which was the original blocker. Good.

**2. A generic-metadata link failure now blocks the decoder specifically.** Linking the test against
`TerminalKitCodecs` fails with

    Undefined symbols: "nominal type descriptor for TerminalKitCodecs.DecoderResult"

`DecoderResult` is fully declared in `Types.swift`, so this is metadata not being emitted for a public
generic across a library boundary — not a missing definition, and not something the move introduced.
It needs a decision (force the metadata, or give the library a `_exported`/resilience setting), and
that decision belongs with whoever owns the kernel module.

## The honest position

An allocation ceiling on `KeyboardDecoder.feed` is **not yet enforced**, and nothing in the project
should imply otherwise. The instrument is ready, verified in both directions, and waiting on one
link-level decision. A principle with an unbuilt guard is still a principle; it is not yet a
constraint.
