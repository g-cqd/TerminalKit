---
status: in-progress
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

## What landed (2026-10-20, ADR-0030)

The model and the clipboard, in the kit and not yet in a screen: `ContentPosition`, `ContentSelection` and `SelectableContent` (a position is
a block, a line and a grapheme offset; reading it back as content); `RowProvenance`, `RowMap`, `LocatedPosition` and `HighlightSpan` (a
drawn row says where it came from, a cell maps back with `TextDisplayMetrics`, a highlight is spans of cells); word and line selection;
and `TerminalIdentity` and `ClipboardWriter` (ADR-0028's rules as a plan the host performs). 40 tests, including that a selection reads the
same and highlights what is visible at three scroll positions and three wrap widths. Position lookup 0.7 to 1.0 µs, highlight of a screen
36 to 58 µs per frame while a selection exists.

## What landed next (2026-10-20, diary 6)

`TextWrap.rows` returns each row with its hard line and grapheme offset, from the same walk as `lines` (no measurable cost, allocations
unchanged). `SelectionController` turns a press, a drag, a release and a click into a selection of content positions: the grapheme under
both ends is included, a backward drag works, a wobble inside the pressed cell selects nothing, a drag at the first or last scrolling row asks
the host to scroll, double and triple click select a word and a line. A drag step is 2.2 µs and allocates nothing. `ColumnSlicer` cuts a
row's text at a highlight's columns so the host can style the middle.

## Still owed

- **Painting the highlight** into a screen without redrawing rows that did not change: the kit gives the spans and the slicer; the diff is the host composer's (ask's `ScreenComposer` keys rows by what they show).
- What a click **inside** an existing selection does (the controller clears it; a drag-to-move is not designed).
- **A selection across a fold or an image** (roadmap 0018), and what a copy contains then.
- **A host recording provenance** as it draws: nothing does yet, in the kit or in ask, so this is untried against a real layout.
- A real-terminal probe that drags across two blocks and reads the clipboard, and tmux, ssh and the primary selection.

## Done when

Selection tests over wrapped, wide and combining text; a selection that survives scrolling, resizing and re-wrapping (the
property test the owner's requirement implies); the highlight costs nothing on unchanged rows in the flush benchmark; a
real-pty probe that drags across two blocks and reads the clipboard.
