---
status: done
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
both (that Page Up figure is void: in that harness the key did not scroll, see step 2). A fresh screen: 14.3 MiB either way. The bound, measured by laying out only the last 50 items: 52.6 MiB and 258 ms to open.

## Step 2 (2026-10-29): laid out from the end, on demand

Positions count from the document's end, as a transcript that follows its end does. `update(width:revisions:keepingFromEnd:layout:)` knows
the heights of the last items only, as far up as `keepingFromEnd` rows need; `lines(fromEnd:rows:layout:)` reaches further up as a window
moves there, and lets go of the lines of held items farther than the margin. A new width forgets every height and lays out from the end
again, so opening and a resize cost the rows on screen and a margin, not the document. Starts are kept in a coordinate that neither appending
nor reaching back moves, so a window is found by binary search and a frame touches the held items only. `rowCount` is the rows of the items
known: exact below any window, the whole document once `isComplete` (at the top). Tests: `WindowedLayoutTests`, 11, among them 2,000 seeded
random steps (edits, appends, cuts, widths, margins, windows) against the whole document.

Measured in ask (release build, a copy of the owner's 12 MB session, 5,564 entries, 120x40, interleaved against the full layout, 2 x 3 runs,
loaded machine; both builds carry ask's fix that lets Page Up scroll before any mouse event):

| | full layout | from the end |
| --- | --- | --- |
| resident size, open and quiet | 60.9 MiB | 52.7 MiB |
| open (spawn to the quiet first frame) | 439-442 ms | 229-230 ms |
| a new width, 120 to 100 columns, 30 pages up | 231 ms | 15-18 ms |
| a typed byte | 1.0-1.3 ms | 0.9-1.3 ms |
| Page Up, median of 30 (worst) | 1.3 ms (1.5-1.9) | 2.5 ms (3.5-5.9) |
| fresh screen, resident size | 14.3 MiB | 14.3 MiB |

A Page Up costs about 1.2 ms more: it lays out the page of items it reaches, which the full layout paid at open. Paged to the top, both
builds draw the same screen with the same 16,148 rows below it. Done: ask uses it, and resident size fell 61.2 to 52.7 MiB over both steps.
