---
status: not-started
blocked-by: ["0016"]
date: 2026-10-20
decision: ADR-0027
---

# 0017 — Selection across rendered text, kept across a scroll, copied to the clipboard

Select text that spans several blocks of what the host drew, keep the selection while the content scrolls, and put the selected
text on the clipboard. Whether it is copied on release is the host's setting (ADR-0027).

## What exists

`TextSelection` and `TextPosition(row, col)` with `extractText`, over a text buffer. `EscapeSequences.setClipboard` writes OSC 52;
`OSCClipboard.parse` reads a reply. `TextWrap` and `LayoutCache` (ADR-0025) split text into rows.

## What is missing

1. **Positions are `Character` offsets, and nothing converts a mouse column to one.** `extractText` uses `line.index(offsetBy: col)`.
   The kit does have the conversion, `TextDisplayMetrics.characterOffset(forDisplayColumn:in:tabSize:)` and its inverse, and
   selection does not use it, so a column from the mouse is wrong on a line with wide or combining graphemes or a tab. *Read from
   the code; not run.* The first test is a CJK line and a tab through the extraction path.
2. **Nothing maps a screen cell to content.** A selection anchored in content (ADR-0027) needs, for every drawn row, the block and
   the source range it came from, and for every cell inside it the grapheme it shows. The layout layer is where that is known:
   `TextWrap` would have to return each row's source range as well as its text.
3. **Drawing the selection.** Painting a highlight at flush time over the intersection of the selection and the visible rows,
   with the attribute the host chooses, and without making the diff redraw rows that did not change.
4. **Dragging past an edge** scrolls (by asking the host) and keeps extending.
5. **Word and line selection** from double and triple click (roadmap 0016's click count), using the grapheme and word boundaries
   the text module has.
6. **The copy.** The text of the selection as content, **not** as drawn: no padding, no separators, no right-aligned hints.

## The clipboard (ADR-0028)

A `ClipboardSink` writes the text. **OSC 52 is the default only where it was measured**: kitty, Ghostty and WezTerm take payloads up
to 1 MB exactly. **Terminal.app ignores OSC 52 entirely**, so it needs the host's pasteboard (ask runs `pbcopy`), and a terminal the
kit does not know gets both. **WezTerm drops the first write after a window opens**, so the first one is sent twice (to validate).
The kit emits "the selection was committed, here is its text"; copying it automatically is the host's setting. A kitty read
prompts, so reading is not used. The native selection returns with Shift (kitty, Ghostty, WezTerm) or fn (Terminal.app).

## Open questions

- A selection that crosses a **folded** block or an image (roadmap 0018): copy the placeholder, or the folded content? A real
  choice with no obvious answer; it belongs to the host's settings once the kit can do either.
- A selection in a block that is **not on screen**, because it scrolled away: kept as anchors; how much of it is extracted is the
  host's to supply (the kit cannot read content it did not draw).
- Rectangular selection, and selecting inside the input (roadmap 0019).

## Probe (done, ADR-0028)

OSC 52 writes, the payload ceiling (none found up to 1 MB) and the native-selection keys are measured. **Still unprobed:** tmux and
ssh, the primary selection, and whether a physical drag selects the same way as the injected one.

## Done when

Selection tests over wrapped, wide and combining text; a selection that survives scrolling, resizing and re-wrapping (the
property test the owner's requirement implies); the highlight costs nothing on unchanged rows in the flush benchmark; a
real-pty probe that drags across two blocks and reads the clipboard.
