---
status: done
blocked-by: ["0006"]
date: 2026-10-19
---

# 0008 — Flush cost proportional to the change

## Evidence (ask's measurement, 2026-10-19, `RenderPipeline` over `MockTerminalConnection`)

A frame changing one cell costs **3 µs at 120×40 and 15 µs at 300×80**. The diff walks only dirty ranges,
so something else scales with the screen: dirty-range iteration, adoption into the front buffer, or the
signposts.

Confirmed by 0006 (`Benchmarks/REFERENCE.md`, a discarding connection): 2.0 µs at 80×24, 3.8 µs at 120×40,
15.5 µs at 300×80, about 0.6 ns per cell of screen.

## What lands

- Find the O(screen) part with the 0006 suite and a profile.
- Remove it, so a one-cell frame costs the same at every size.
- Keep ADR-0016's zero-allocation ceiling.

## Done (2026-10-19)

The part that scaled with the screen was the copy into the front buffer: `adoptDirtyCells` tested every
cell's dirty bit. It now walks the set bits a word at a time. The dirty tracker also remembers which words
were touched, so clearing, `isEmpty` and the range walk visit only those. One-cell flush, p50:

| | 80×24 | 120×40 | 300×80 |
|---|---|---|---|
| Before (`REFERENCE.md`) | 2.0 µs | 3.8 µs | 15.5 µs |
| After | 0.83 µs | 0.79 µs | 0.79 µs |

The cost no longer depends on the screen's size. The rest of the suites moved with it: one row 2.1 instead
of 4.8 µs at 120×40, and a streamed line 12 instead of 15 µs (diary 2026-10-19-08).
