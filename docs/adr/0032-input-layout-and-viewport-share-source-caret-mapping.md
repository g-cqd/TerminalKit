---
status: accepted
date: 2026-10-22
---

# 0032 — Input layout and viewport share source-caret mapping

## Context

Roadmap 0019 needs a bounded input that scrolls by display row, while `TextNavigation.ensureVisible` addresses hard lines. ask's renderer
and editor calculate different rows: its renderer wraps, its editor navigates hard lines, and a cursor just before a soft-wrapped character
can be reported one cell beyond the terminal edge. Prefix width, wide characters and tabs make a second independent walk unreliable.

## Decision

- `InputLayout` maps source `Character` boundaries to hard-wrapped display rows, and display cells back to source offsets. It owns no
  editing keys, screen policy or host prefix text. The host reserves a first-row prefix in display cells.
- A soft-wrap boundary belongs to the following row; an exactly full input gets an empty cursor row. Before a hard newline at the right
  edge, the caret shares the following row's first cell. It never sits on a wide continuation cell or invents another blank row.
- Mapping is not always injective: zero-width characters and the shared newline cell can have equal caret cells. A cell lookup chooses
  the last equal boundary. Tests require cell round trips, not a false promise of unique offset round trips.
- Newlines start rows; tabs expand to tab stops without changing source offsets. Controls display as U+FFFD, matching `ScreenBuffer`.
  If the viewport is narrower than a whole grapheme, `?` occupies one cell; the original input is not changed.
- Nonpositive widths become one column; the prefix reservation is clamped to leave an editable cell. A prefix-only row can have no source
  caret and maps to the next editable row. These contracts keep tiny terminals safe without splitting a grapheme.
- `InputViewport` takes the layout, source cursor, requested row limit and previous top row. It clamps the window, preserves it while the
  cursor is inside, and moves only as far as necessary otherwise. It reports rows above/below for a host-drawn indicator.

## Cost and ownership

Building the layout is O(b + e), for source UTF-8 bytes b and rendered bytes e, with O(n + e) storage for n graphemes. Caret lookup is O(1),
reverse mapping O(log n), and viewport updates O(1). Hosts should cache the layout across cursor-only changes.

ask chooses the `ui.promptRows` default and viewport-fraction cap, supplies its prefix, routes keys and draws the clipping indicator. It
can adopt this shared mapping without replacing its editing model with `TextBuffer` in the same change. Existing hard-line editor APIs
remain useful to hosts without a display width; display-aware callers pass one explicitly.

Mouse placement/selection and wheel scrolling inside an input are separate integration work, not implied by these two value types.
Evidence and measured costs: diary 2026-10-22 (1).
