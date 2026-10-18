---
status: accepted
date: 2026-10-18
supersedes: the isolation rule in 0008
---

# 0016 — The input router and frame flush allocate nothing, and every release suite checks it

## Context

ADR-0008 set a zero ceiling for the keyboard decoder and ran it opt-in, in its own CI job, because
other suites' threads leaked into Aemi's counter. Entry 0004 still owed ceilings for the input router
and the renderer's frame flush. Aemi ADR-0010 now counts only the measuring thread.

## Measured before the fixes (release, per event or per flush)

| Workload | Allocations | Cause |
|---|---|---|
| Text, single keystrokes | 0 | — |
| Escape key | 1 | `buffer = [byte]` replaced the router's buffer on every ESC |
| Arrow key | 2 | the same, plus the next `append` growing the one-byte array |
| Kitty key, SGR mouse | 3 | the same, plus `decodeKeyboardSequence` returning an array, or `MouseDecoder.reset` calling `removeAll()` |
| Two-byte UTF-8 | 2 | `utf8Buffer = [firstByte]`, then growth |
| 1 KiB paste | 5 | the ESC buffer, growth, and a `dropLast` slice still alive when `resetRouting` cleared the buffer, forcing a copy |
| Full-screen flush | 11 | `dirtyRanges` building a growing array, plus signposts |
| Idle flush | 4 | `OSSignposter` interval states are objects: 3 per interval, and signposts are enabled by default |

## Decision

- The router reuses its buffers (`removeAll(keepingCapacity:)` then `append`), appends decoded keys
  into the caller's array, ends the paste slice before resetting, and `MouseDecoder` keeps capacity.
- `DirtyTracker.forEachDirtyRange` walks dirty runs without materializing them; `dirtyRanges` stays
  as API on top of it, and `DiffRenderer` uses the walk.
- Signposts use `os_signpost` with a value `OSSignpostID` under the same subsystem and names: measured
  at 0 allocations against `OSSignposter`'s 3. Instruments shows the same intervals.
- Ceilings: every key kind 0 per read, a paste at most 1 (its `String`), and a flush 0 whether idle,
  changing every row, or scrolled. The three render cases sum all eight measured flushes, so a
  regression on alternate frames cannot hide behind a minimum.
- All ceilings, the decoder's included, run in the default suite and are disabled only in debug
  builds. The opt-in variable and the separate CI job are removed.

## Consequences

- Each new case failed before its fix with the counts above and passes after; the full gate reports
  397 tests across seven executables, exit 0, with every allocation test executed.
- A debug `swift test` skips the ceilings; the release gate enforces them.
- Allocations a measured body hands to another thread are not counted (Aemi ADR-0010). All ceilings
  here measure synchronous work on one thread.
