---
status: accepted
date: 2026-10-19
---

# 0022 — A scroll region is declared once, its shifts are detected, and short gaps are written over

## Context

A bottom-aligned transcript shifts every row when a line arrives, and the diff rewrites every changed
cell of every row. `ScrollHint` could already scroll the terminal (DECSTBM, then SU or SD), but the
application had to say, frame by frame, how far its rows had moved relative to what the terminal shows
(roadmap 0011).

## Decision

- **`RenderPipeline.scrollRegion: Range<Int>?`**: the rows that scroll together, set once.
  - When at least two of its rows changed, `flush()` hashes the region's rows and scores every shift by
    how many rows it leaves in place. If the best shift beats leaving them alone, the pipeline scrolls the
    terminal by it.
  - The front buffer's row hashes are kept from flush to flush. After a flush the front buffer equals the
    back buffer, so only the rows a frame changed are hashed again. A resize, a forced redraw, a region
    change or an explicit hint invalidates them.
  - A hash collision costs bytes, never correctness: after any scroll, every cell of the region is still
    compared before the diff.
- **An explicit `scrollHint` still wins.**
- **The diff writes a short unchanged gap instead of moving the cursor over it**, when that is fewer bytes
  than `ESC [ row ; col H` and needs no style change. This applies to every frame. It is what makes a
  scrolled-in row cheap: its spaces match the blank row the scroll exposed, and were each costing a
  cursor move.
- DECSTBM, SU and SD are VT100. Every terminal ask targets has them.

## Measured (`stream/…` benchmarks: ask's transcript of numbered word lines, layout writes plus flush)

| | 80×24 | 120×40 | 300×80 |
|---|---|---|---|
| Bytes per streamed line, no region | 228 | 413 | 817 |
| Bytes per streamed line, scroll region | 116 | 151 | 301 |
| Time, no region (p50) | 6.5 µs | 15 µs | 63 µs |
| Time, scroll region (p50) | 10 µs | 22 µs | 98 µs |

- **Bytes:** a streamed line costs 49–63 % fewer bytes. The CPU cost rises by 4–35 µs, for hashing the
  changed rows and comparing the region after the scroll. No allocation in either case.
- **Getting there:** the first version took 44 and 214 µs. Three changes cut it:
  - the post-scroll comparison went through spans instead of class-property subscripts;
  - the shift went through a mutable span;
  - the row hashes were cached across frames.
- **Real terminals** (`Scripts/verify-scroll-region.sh`, which runs the real pipeline inside each and reads
  the screen from outside): kitty 32 of 32 rows, wezterm 24 of 24, Terminal.app 24 of 24, after 25
  streamed lines inside synchronised output. ghostty has no text reader and is not checked.

## Consequences

- The diff now writes unchanged cells when that is shorter. One regression test asserted the old
  behaviour ("unchanged cells are not emitted"). It now asserts the gap is written.
- Whether an application sets a scroll region is a trade of bytes for microseconds. A terminal over SSH, or
  one slow to parse, gains most.
- `Scripts/benchmarks.sh compare` falls back to the base's own benchmarks when this tree's do not build
  there (a change that adds an API along with its benchmark). The suites both trees have are still
  compared.
