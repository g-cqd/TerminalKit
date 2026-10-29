---
status: not-started
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
