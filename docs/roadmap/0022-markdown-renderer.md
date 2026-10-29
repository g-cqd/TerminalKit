---
status: not-started
blocked-by: ["AemiMarkdown finished"]
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
