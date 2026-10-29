---
status: in-progress
blocked-by: []
date: 2026-10-29
---

# 0023 — Lay out only the rows that are shown

`LayoutCache` keeps every line of every item, so a resumed session of 1,930 responses holds 3 MB of line array and builds all of them. Measured
in ask (roadmap 0088): resident size 53 to 55 MiB; trimming the live heap did not lower it, because freed pages stay resident. Only touching
fewer pages lowers resident size, so the lines of what is far off screen must never be built.

## Design to try

Keep per item the **row count** (and revision), as `BlockHeights` already does for folds, and lay out an item's lines only when a row of it is
in the viewport or in a margin around it. A row index then resolves by binary search over the starts (already how `BlockHeights.anchor`
works), and an item's lines are built on demand and evicted when far away. A height must be known without the lines, so the first layout of
an item at a width computes its height only; text-only items can do that by counting wrapped rows without building cells.

## Measure first

Release build, resident size and frame time before and after, on the 1,930-response session and on a fresh one, so that the idle budget (15 MiB)
is not made worse for the sake of the long case. Streaming must still lay out only the last item.

## Done when

`LayoutCache` (or a sibling) can serve `lines[range]` for a window without holding the rest, ask uses it, and the RSS figure above falls
by a measured amount.

## Step 1 (2026-10-29): `WindowedLayout`

`WindowedLayout<Line>` keeps every item's revision, row count and start, and the lines of the items near the window only. `update` lays out
the changed items last first, so how far an item ends from the end is known when its lines exist, and keeps those within `keepingFromEnd`
rows; `lines(in:)` lays out what the window shows and lets go of what is farther than a margin (one window by default). A height is still
found by laying the item out and dropping its lines, so the first layout and a new width cost what they did; only the holding changed.
Tests: `WindowedLayoutTests` (windows anywhere equal the whole document, far items let go, streaming lays out one item, empty items).

Measured in ask (release build, interleaved A/B, 3 to 4 runs each, a copy of the owner's 12 MB session, 5,564 entries, 120x40, loaded
machine): resident size 61.2 to 54.9 MiB; open 545-664 to 504-636 ms; a new width 302-354 to 225-254 ms; typing and Page Up under 1 ms
both. A fresh screen: 14.3 MiB either way. The bound, measured by laying out only the last 50 items: 52.6 MiB and 258 ms to open.

Next: heights found from the end on demand, so opening and a new width lay out only what is shown and the rows below the window are exact
while the total above it is an estimate refined as the window moves up.
