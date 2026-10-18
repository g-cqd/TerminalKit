---
status: not-started
blocked-by: ["0006"]
date: 2026-10-19
---

# 0007 — Compact cells: memory and compare cost proportional to what is shown

## Evidence (ask's measurement, 2026-10-19)

- `Cell` is 35 bytes, stride **40**: a `Character` (16) and a `Style` (18, three colours and flags), plus a
  width byte.
- Two grids at 120×40 are **393 KB**, the largest allocation in ask's idle heap. At 300×80 they are 1.9 MB.
- Rewriting a row of identical text costs about **16 ns per cell** (77 µs at 120×40, 380 µs at 300×80,
  p99 27 ms), comparing `Character` and `Style` for every cell.

## Direction, to be probed before adopting

- **The grapheme** inline when its UTF-8 fits (8 bytes covers ASCII, most CJK, and many emoji), else an
  index into a per-buffer grapheme table.
- **The style** as an index into a per-buffer palette (`UInt16`): a screen uses few distinct styles.
- **Target ≤ 16 bytes per cell,** with an integer compare.

**Probes first:**
- the grapheme length distribution over real transcripts;
- palette size in practice;
- `DiffRenderer` and `SGREncoder` cost when styles are looked up by index.

## Done when

The ScreenBuffer suites in 0006 show the compare cost and memory drop, with the frame output byte-identical.
