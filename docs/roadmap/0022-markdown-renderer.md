---
status: done
blocked-by: []
date: 2026-10-29
---

# 0022 — `TerminalKitMarkdown`: a Markdown document drawn as rows of cells

Wanted by ask 0065 (markdown in the transcript), 0086 and 0085 and by Atelier. The parser is AemiMarkdown (CommonMark and GFM, MIT, being
finished); the kit owns the drawing, so that a host never turns a tree into escape sequences itself.

## Shape

A separate target depending on `TerminalKitText` and `TerminalKitStyle` and on AemiMarkdown, so a host that does not render Markdown does not
link it (the white paper's link-weight rule). Input: a document (or the change to one, for streaming) and a width. Output: lines of styled
cells that `LayoutCache` can hold, with each line's source range, so selection copies the Markdown or the text as the host chooses.

## Needs from AemiMarkdown first

Stable block identity across a streamed edit (so the cache keeps lines of blocks that did not change), a walker that does not allocate a
tree per frame, and green default tests. Tracked in the schedule document in ask (`development/research`).

## Open

Code blocks highlighted by AtelierLexers (ask 0087) through a protocol, not a dependency; tables narrower than the width; OSC 8 links; images
(roadmap 0018) as placeholders first.

## Unblocked (2026-10-29)

AemiMarkdown `029235c` has what this entry waited for: `MarkdownDocument.topLevelBlocks` with stable identities and parser-based finality, and
`events(of:)` to walk one block (its ADR-0002, a byte-at-a-time property test over every spec example); green default tests; DocC; a fresh benchmark
(200 MB/s, 35 allocations per KB, a 100 KB answer streamed in 0.005 s); and a cmark comparison with 4 known differences in 5,000, all cmark's.
Still not there: a source byte range per block, and a revision for the open block. A fresh walk allocates its two stacks (two allocations, none per
node); keep one walker and `restart(at:in:)` it per block and a walk allocates nothing once warm (AemiMarkdown `3308985`, allocation suite). A block
source range is deferred until this renderer asks for one (AemiMarkdown ADR-0002); the leaves' ranges cover row-to-source mapping.


## Built (2026-10-29)

The `TerminalKitMarkdown` product, pinning AemiMarkdown `2e75a94` (same Aemi revision as the kit). Decisions in ADR 0033.

- `MarkdownRenderer.lines(of:in:width:)` lays out one top-level block into `StyledLine`s (runs of text, `Style`, and the source bytes each
  run shows; chrome has none). A final block's rows depend on the block and the width only, so a host keys them by `MarkdownBlock.id` and lays
  out only the open block again as an answer streams; a test streams a document 5 bytes at a time and checks exactly that.
- Paragraphs and headings wrap like `TextWrap` (a test compares them at seven widths); quotes and alerts take a bar, list items a marker then
  its width, footnote definitions their label; a prefix never takes more than half the row. Code blocks keep their lines after a gutter, tabs
  to stops of four, cut at the width; a `MarkdownCodeHighlighter` the host gives colours them (no lexer dependency). Tables take natural
  widths, then shared widths with cells wrapped, then a `header: value` record per row.
- Links through a `MarkdownLinks` policy: an OSC 8 hyperlink only for an allowed scheme (http, https, mailto) or what `resolve` maps a path to,
  printable ASCII only; the target written after the text when the text names another host (`whenMisleading`, the default).
- Control graphemes are never drawn (ESC in a model's answer stays inert); entities show decoded over their source bytes.

Properties over 13 hand-written and 150 seeded random documents at every width 1 to 100: no row wider than the width (a wide grapheme at width
1 excepted), every printable source byte of text, HTML, code, entities and footnote labels shown by some run, every run's text its source as
written or decoded, and a reused renderer equal to a fresh one. Cost in release: 0.9 ms to lay out a 17 KB document (77 blocks, three of the
repository READMEs) at one width, 55 µs for its largest block.

Not done: images are their alt text in brackets (roadmap 0018 is the real thing); math is shown as written in the code style;
ask's integration is its roadmap 0065.
