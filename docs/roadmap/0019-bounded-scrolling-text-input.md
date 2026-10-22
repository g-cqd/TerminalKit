---
status: in-progress
blocked-by: []
date: 2026-10-20
decision: ADR-0032
---

# 0019 — A text input bounded in rows, scrolling inside itself

Limit an input to a maximum number of rows and scroll within it, keeping the cursor visible. The host sets the maximum.

## What exists, and where

The kit has more of it than ask uses. `TextNavigation.ensureVisible(cursor:visibleRows:visibleCols:wrapLines:)` keeps a cursor in view
by moving `scrollRow` and `scrollCol` on a `TextCursor`, with `visibleRows` as the cap; `TextBuffer`, `TextCursor` and
`TextOperations` do the editing; `TextDisplayMetrics` converts display columns and character offsets.

**ask does not use any of it.** `PromptEditor` imports the text module and holds its own lines and cursor, and `ScreenComposer`
caps the prompt with a hard-coded `maximumPromptRows` (six) and computes the first visible line itself (ask roadmap 0049, done).
No ask source mentions `TextBuffer`, `TextCursor` or `TextNavigation`. It is the opposite of roadmap 0012, where ask had the
better code and the kit adopted it: here the kit has the primitive, and the host wrote its own.

## What is still missing

- **Wrapped lines.** `ensureVisible` works on hard lines (`cursor.row`) and, with wrapping on, only resets the column. ask's editor
  moves between hard lines only for the same reason (0049 still owes this). A viewport that knows the layout width and scrolls by
  display row is the missing piece, and it is what a bounded input of N rows needs.
- **The wheel inside the input** scrolls it and not the transcript; **a click** places the cursor (roadmap 0016); **a selection**
  inside it uses roadmap 0017.
- A scroll indicator for a clipped input, drawn without a row of its own.

## What landed (2026-10-22, ADR-0032)

`InputLayout` shares the hard-wrap and source-caret map: prefix reservation, wide/combined graphemes, tabs, controls, exact boundaries and
safe tiny sizes. `InputViewport` caps display rows, keeps the source cursor visible, preserves the existing window where possible, and
reports clipped rows for an indicator. Seventeen new tests, including generated geometry checks; 622 release tests pass. A fresh ~6 KB
layout costs about 240 µs, cached mapping about 33 ns and viewport updates about 11 ns with no allocations (diary 2026-10-22 (1)).

Host adoption, its clipping indicator, input mouse/wheel/selection and terminal verification remain owed.

## Open question

Whether ask should adopt the kit's types first (a refactor that must leave the editor tests unchanged) and only then add wrapped
rows to the kit, or add them in the kit and move ask over in one step. The first costs a step and shows whether the kit's types fit
a real editor before they grow.

## Done when

A viewport in the kit that scrolls by display row, with tests for the cap, wrapped lines and wide graphemes; ask's editor using it
with its output unchanged on the existing editor tests; the input and render path measured before and after in release.
