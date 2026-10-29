---
status: accepted
date: 2026-10-29
---

# 0033 — Markdown is drawn per top-level block into styled runs that name their source

## Context

ask (0065, 0085, 0086) and Atelier need a model's Markdown answer drawn in a terminal transcript: streamed a few bytes at a time, at any
width, selectable and copyable as source, and safe, since the answer is untrusted text. AemiMarkdown gives top-level blocks with stable
identities and finality, and an event walk of one block with a byte range on every leaf.

## Decision

- The unit is a top-level block. `lines(of:in:width:)` returns its rows; the rows of a final block depend on the block and the width only, so the
  host caches them by block identity (with `WindowedLayout`) and lays out only the open block per streamed chunk. The renderer holds no
  per-document state; it keeps one event walker so a warm walk allocates nothing for its stacks.
- A row is runs of text, a `Style`, and `source: Range<Int>?`: the bytes the run shows. Text shows its bytes one for one, so a part of a
  wrapped word maps to the matching part of its range; a decoded entity or an expanded tab shows its whole range; chrome (markers, bars,
  padding, rules, link targets) has nil. A host maps a selection to source by the runs it covers, with no second walk.
- The output is not cells. `StyledLine` is text and styles; the host's screen turns it into cells, so ask keeps its own line type and
  composer. Widths come from `UnicodeWidth`, the same table as the screen.
- Containers become prefixes, not indentation of their own rows: a quote's bar on each row, a list item's marker then its width. A prefix
  keeps its innermost columns and takes at most half the row (less when a wide grapheme needs the room), so deep nesting never hides the text.
- Links follow a policy, not the parser: a hyperlink only for allowed schemes or a host's `resolve`, printable ASCII only, and the target
  written out when the text names another host. Control graphemes are dropped, never drawn.
- Tables fit the width by a fixed rule: natural widths; else at least the longest word, spare shared in proportion; else one record per row.
  A table is never cut at the edge.
- Code is coloured through `MarkdownCodeHighlighter`, a protocol the host implements; the kit links no lexer.
- A soft break is a space by default, as CommonMark says. `softBreaks: .lineBreak` makes it a new row (still a space inside a code span), for
  a chat transcript, where a model that ends a line means a new one.

## Consequences

The rows of a block are a pure function of the block's events, theme, link policy, highlighter, soft-break choice and width, which is what the property tests
check. A theme change or a policy change means laying out again; a host keys its cache by them too. Spacing between top-level blocks is the
host's (`lines(of:width:)` puts one blank row), so a transcript can choose its own.

Evidence: roadmap 0022 and diary 2026-10-29 (1).
