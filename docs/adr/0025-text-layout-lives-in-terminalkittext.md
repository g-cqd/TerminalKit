---
status: accepted
date: 2026-10-19
---

# 0025 — Word wrapping and the revision-keyed layout cache live in TerminalKitText

## Context

ask wrote `TextWrap` (word-wrap by display width, wide characters as two columns) and, in its screen
composer, a cache of wrapped lines keyed by each transcript item's revision. Neither is specific to ask: any
terminal app that streams text rewrites both (roadmap 0012, ADR-0007).

`TextWrap` walked the text grapheme by grapheme, appending each to a `String`: 230 µs for a 4 KB paragraph at
80 columns, about 56 ns a byte, with 213 allocations.

## Decision

- **`TextWrap.lines(_:width:)`** moves to `TerminalKitText`, with ask's tests and more.
- **It walks bytes.** An ASCII byte followed by an ASCII byte or the end is a grapheme of its own, one column
  wide (zero for NUL), and needs no segmentation. Anything else, and a carriage return, which can pair with
  a line feed, is segmented from where it starts, with the same character iterator `ScreenBuffer.write` uses.
  Lines are cut at grapheme boundaries and built once, from byte ranges.
- **`LayoutCache<Line>`** holds the lines of a document laid out item by item. `update(width:revisions:layout:)`
  lays out the items from the first whose revision changed, and all of them when the width changes.
- The grapheme-by-grapheme original stays in the test target as an oracle.

## Measured (`wrap/…` suites: one 4 KB body per sample, p50)

| Body | Before | After | Allocations |
|---|---|---|---|
| Prose at 80 | 236 µs | 19 µs | 213 → 59 |
| Prose at 120 | 230 µs | 19 µs | 125 → 41 |
| Code at 80 | 230 µs | 19 µs | 169 → 59 |
| Mixed CJK and English at 80 | 153 µs | 56 µs | 154 → 43 |

About 4.6 ns a byte for ASCII. The per-line `String` and the result array are the allocations left.

## Evidence

- The oracle test compares both versions on 27 hand-picked texts (CRLF, lone CR, NUL, tabs, combining
  marks, ZWJ families, flags, skin tones, wide characters, leading line feeds) at nine widths, and on 3,000
  generated strings.
- Negative controls: counting NUL as one column fails 3 hand-picked cases and the generated run; letting
  a carriage return take the fast path fails them too.
- `LayoutCache`: nine tests on which items are laid out for a new item, a changed item, a streamed last item,
  a new width, fewer items, an emptied document and `reset()`. Written against a stub, red.

## Consequences

- ask's `TextWrap` and the cache fields in `ScreenComposer` are deleted.
- The cache trusts revisions. A producer that changes an item without changing its revision shows stale
  lines; the same contract ask already had.
