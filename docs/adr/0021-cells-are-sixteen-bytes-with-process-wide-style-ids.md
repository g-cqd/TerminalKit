---
status: accepted
date: 2026-10-19
---

# 0021 — Cells are sixteen bytes, with styles and long graphemes numbered for the whole process

## Context

A `Cell` was a `Character` (16 bytes), a `Style` (18) and a width: 35 bytes, stride 40. Two grids at
120×40 took 393 KB, the largest allocation in ask's idle heap. Comparing two cells compared a grapheme
and three colours, about 14 ns per cell, so rewriting an unchanged screen cost 69 µs at 120×40 (roadmap
0007, `Benchmarks/REFERENCE.md`).

## Probes

- **Grapheme lengths:** 189,591,381 graphemes from 139 agent transcripts (225 MB):
  - 99.9998 % are 4 UTF-8 bytes or fewer;
  - all but 7 are 8 bytes or fewer. Those 7 are ZWJ emoji of 11 to 25 bytes.
- **Styles in practice:** ask's composer draws 6 distinct styles. KittyCode's colour scheme names about
  60.
- **Index lookup in the diff:** measured by the benchmarks below. A style is looked up only where it
  changes between emitted cells.

## Decision

- `ScreenBuffer` stores `PackedCell`, 16 bytes compared as two `UInt64`s:
  - the grapheme's UTF-8 bytes inline when they fit in eight, otherwise an index into `GraphemeTable`;
  - the length;
  - the width;
  - a `UInt32` style id from `StyleTable`.
- **`StyleTable` and `GraphemeTable` are process-wide**, `Mutex`-guarded and append-only. One numbering
  for every buffer is what lets a front and a back buffer compare cells by id. A buffer remembers its
  last style, so consecutive writes in one style take no lock.
- **The public API is unchanged:**
  - `Cell` stays the value type callers read and write;
  - `buffer[row, col]` decodes and encodes;
  - `cells` decodes the whole grid, and now builds an array on each call.

## Measured (`Scripts/benchmarks.sh compare`, load average 12, p50 before → after)

| Suite | 80×24 | 120×40 | 300×80 |
|---|---|---|---|
| write, identical text, every row | 28.9 → 4.7 µs | 69 → 11 µs | 340 → 52 µs |
| write, new text, every row | 40.9 → 7.2 µs | 98 → 17 µs | 498 → 83 µs |
| flush, every cell | 110 → 20 µs | 282 → 48 µs | 1,360 → 232 µs |
| flush, one row | 6.9 → 2.7 µs | 10.4 → 4.8 µs | 32 → 18 µs |
| forceRedraw | 40.8 → 6.3 µs | 101 → 15 µs | 513 → 74 µs |
| flush, one cell | 2.0 → 2.0 µs | 3.9 → 3.8 µs | 16 → 16 µs |

- An unchanged cell now costs about 2.3 ns, against 14 ns before.
- Two grids at 120×40 take 154 KB, against 393 KB.
- No suite allocates more: every frame suite is still at 0.
- The one-cell flush is unchanged: its cost scales with the screen for another reason, roadmap 0008.

## Consequences

- **Cells compare by bytes, not by canonical equivalence.** `é` written over `e` + U+0301 is now a
  change and is redrawn. Before, `Character` equality called them equal and the terminal kept the old
  spelling. Red on the old code, green now.
- **The tables never shrink.** A program that generates styles without bound grows `StyleTable` by about
  one `Style` and one dictionary entry per style. That is acceptable for the measured practice (tens of
  styles). A program that animates colours would need a different policy, decided on its numbers.
- Reading a cell through the subscript takes the style table's lock unless the style is the default.
  That is fine for inspection and tests; frame work goes through the packed cells.
