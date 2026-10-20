---
status: accepted
date: 2026-10-20
---

# 0029 — Pointer input is recognized as clicks, drags and wheel steps, over regions the host names

## Context

Roadmap 0016 asks that a host can say "this rectangle is the thinking block `b42`" and be told when it is clicked. TerminalKit
decoded mouse reports (`MouseDecoder`) and delivered them as `InputEvent.mouse`, and nothing above that understood them. ADR-0028
measured what four terminals send; this decides how the kit turns it into something a host can act on.

## Decision

1. **A region is a rectangle of cells and the host's identity for what is there** (`RegionMap`, `CellRect`). The host clears the map
   and re-adds its regions every frame, since scrolling moves everything. Identity is the host's type, `Hashable & Sendable`, never a
   position, so a block is the same target before and after it moves (ADR-0027). A region has a layer, so a popup sits over the
   transcript, and among equals the one added last is on top.
2. **A recognizer turns reports into what the pointer did** (`PointerRecognizer`): a click (with a count of 1, 2 or 3), the start,
   moves and end of a drag, and a wheel step. A press and a release on the same target with no motion between is a click; movement of
   at least `dragThreshold` cells (1 by default) makes it a drag, which belongs to selection (roadmap 0017) and not to what is under
   the pointer. The host chooses nothing about what a click means.
3. **Coordinates are made zero-based in one place.** The decoder passes the terminal's one-based cells through; the recognizer
   subtracts one, so nothing the host sees is one-based. A pixel-mode report, which carries no cell, is ignored.
4. **A release that arrives with no motion before it, far from the press, is a drag.** Mode 1000 alone reports no motion, and the
   gesture is only known to have been a drag from where it ended.
5. **A click needs the pointer to be over the same target at release as at press.** This only matters when content moves under a
   still pointer, such as a scroll between the two, and then it is not a click on what is there now.
6. **A wheel step is one report, and the host decides what it scrolls**, because terminals send 1, 3 or 9 reports for the same
   gesture (ADR-0028).
7. **No hover.** Motion with no button is ignored: it needs any-motion reporting (`?1003`), which is far more input, and nothing
   asks for it yet.
8. **The recognizer reports through a closure that does not escape**, and the map keeps its storage when cleared, so recognizing a
   report allocates nothing (ADR-0016). The ceiling is zero, held by a test.
9. **The scan over the regions is not generic.** `RegionMap<ID>` keeps the geometry in a non-generic `RegionGeometry` (rectangles
   and layers as plain integers) and only turns the index it finds back into an identity.

## Evidence

- **Tested against the bytes terminals send.** The kitty, Ghostty, WezTerm and Terminal.app streams recorded by the probe
  (ADR-0028) are replayed through the decoder and the recognizer: kitty and Ghostty give a click, an Option-click, two drags and the
  wheel, and nothing for Shift; WezTerm gives modifier-free clicks and drags because it sends no alt bit; Terminal.app gives Shift
  and Option as modifiers.
- **Five mutations of the code are caught**: forgetting the zero-based conversion, the wrong tie rule between regions, a click
  count that never wraps, a click that ignores the target, and an allocation in `hit`. One of them was **not** caught at first: the
  test named for "a release on a different target" never reached the branch, because moving two rows is already a drag. It now has
  a test where content moves under a still pointer.
- **Measured, release, 120 regions** (`pointer/*` and `regions/hit` in the input benchmarks). A generic scan did a hit in
  **2,927 ns**; the same code compiled in one module did it in 85 ns. The difference is specialization across a module boundary,
  and `@inlinable` recovered only 13%. Moving the scan into a non-generic type made it **119 ns** through the benchmark, and a
  click 3,226 to **345 ns**, a drag 718 to **161 ns** and a wheel step 3,117 to **230 ns** per event, all with zero allocations.

## Consequences

- A host has what roadmap 0016 asked for, and roadmap 0017 (selection) can start from drag events.
- The recognizer holds one press, so it is single-pointer. Multi-touch is not a terminal concern.
- `RegionGeometry` is internal. If a host wants ids that are not `Hashable & Sendable`, the map would take an index instead, which the
  structure already allows.

## What this does not decide

How a host registers regions as it draws (that is the composer's, and the integration with `RenderPipeline` is open), whether every
click has a keyboard equivalent, hover, and what a click inside an existing selection does (roadmap 0017).
