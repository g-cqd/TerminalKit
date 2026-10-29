---
status: accepted
date: 2026-10-20
---

# 0030 — A selection names its content, and every drawn row says where it came from

## Context

ADR-0027 requires that a selection is anchored in content and survives scrolling. Roadmap 0017 asks for selection across what is
drawn, a highlight, reading it back, and the clipboard. The kit had `TextSelection`, in row and column of a buffer, which knows
nothing of the screen. This decides the model that does.

## Decision

1. **A position is a block, a line and a grapheme offset** (`ContentPosition`). The block is the host's own identity, so scrolling,
   resizing, re-wrapping and blocks added above do not move it. A line is a hard line of the content, so a line that wraps is still
   one line, and the offset counts `Character`s, which is what text is cut by.
2. **The host tells the selection about its content through `SelectableContent`**: the blocks in reading order, the line count of
   each, a line's text, and a block's current index. A selection stores identities and asks for indices only when it compares or
   reads, because an index changes when content is added above it.
3. **Every drawn row says where it came from** (`RowProvenance`, kept for a frame in `RowMap`): the block and line, which graphemes
   of it this row shows, the cell it starts at, and the text drawn. The layout layer knows this, since it split the line into rows.
   A row with none (padding, a separator) holds no content.
4. **A cell maps back to content through the row, with the kit's own width code** (`RowMap.position`), so wide graphemes and tabs
   agree with `TextDisplayMetrics`. It has an edge: before the grapheme under the pointer, where a selection starts, or after it,
   where a forward drag ends so that the grapheme is included. A drag over padding snaps to the nearest content row (`nearestPosition`).
5. **The highlight is spans of cells, and the host paints them** (`RowMap.highlights`). Only the intersection with the visible rows is
   returned, so a selection partly scrolled away highlights what is on screen and stays whole in the content.
6. **The selected text is content, not what was drawn** (`ContentSelection.text`): no padding, separators or hints, lines joined by
   `\n` and blocks by a separator the host picks. Positions past the end are clamped, since the content may have changed, and a
   selection whose block is gone reads as nothing.
7. **Double and triple click select a run and a line** (`word(at:)`, `line(at:)`): letters, digits and `_` are one run, spaces
   another, anything else a third.
8. **The clipboard is planned, not performed** (`ClipboardWriter.plan`): it returns the bytes for the terminal and whether the host
   should use its pasteboard, so it is testable without a terminal. It follows ADR-0028: OSC 52 unless the terminal is known to ignore
   it or the text exceeds 1,000,000 bytes, the pasteboard when the terminal is not known to take OSC 52 (never over a remote
   connection), and the first write sent twice on WezTerm. An empty copy changes nothing.

## Evidence

- **40 tests** across selection, mapping, scrolling, highlighting, word and line, identity and the clipboard. The scroll test is the
  owner's requirement: the same selection reads the same text and highlights what is visible at three scroll positions, and a
  re-wrap at three widths highlights the same five cells.
- **Ten mutations are caught**: the trailing edge ignored, the highlight ignoring where the selection ends, a tie that snaps the wrong
  way, `_` not part of a word, a backwards selection not put in reading order (this one crashes the test process, so it is caught but
  not tidily), WezTerm's first write not repeated, Terminal.app sent OSC 52, the pasteboard used over a remote connection, the ceiling
  off by one, and an empty copy not skipped. Two of my first mutations were wrong (one did not compile, one was the reverse of its
  label) and were redone.
- **Measured, release** (`selection/*`): a position lookup 692 ns on ASCII and 1,044 ns on CJK, with zero allocations; the highlight
  of a 40-row screen 36 and 58 µs, with 86 allocations; reading 8 blocks back 15 and 30 µs, with 7. The highlight is once per frame
  while a selection exists, so its cost is small against a frame; the allocations are unexplained and were not chased.

## Consequences

- A host that records provenance as it draws gets selection, highlighting and copying without the kit knowing what a block is.
- `TextSelection`, the buffer selection, is unchanged and unrelated: it is for editing a buffer, this is for reading drawn content.
- The host owns what is copied when (copy on release is its setting, ADR-0027), and the kit never copies by itself.

## What this does not decide

How the highlight is painted into `RenderPipeline`'s buffer, the drag controller (anchor and head edges, autoscroll past an edge, and
a click inside an existing selection), a selection across a folded block or an image (roadmap 0018), how a layout layer should record
provenance cheaply, and keyboard selection.

## Amended 2026-10-29: a row of several segments

A row of rendered Markdown (ADR 0033) shows several stretches of its source, with markers hidden and chrome added between them, and a soft
break joins two source lines on one row. `RowProvenance.segments` lists them (`RowSegment`: line, first offset, column, drawn text, and how
many graphemes of source it shows); the original fields are the first segment, so a plain row is unchanged. A segment whose drawn text is as
long as its source maps cell to grapheme; one that is not (a decoded entity, a tab drawn as spaces) is atomic. A highlight paints the chrome
between two segments only when the selection runs through both. The content is still the source, so a selection copies the Markdown it
spans, markers included, which is what ask decided (its roadmap 0065). A position at a segment's first grapheme (leading) or after its last (trailing) reaches across the
source no cell draws between it and its neighbour on the same line and row, so selecting a bold word copies `**bold**` and not `bold**`.
A plain row has one segment, so nothing changes for it.
