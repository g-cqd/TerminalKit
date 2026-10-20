---
status: accepted
date: 2026-10-20
---

# 0027 — Selection, clicks and folding are the kit's; their policy is the host's

## Context

The owner asked, while reviewing a prototype of ask's screen, for four things that no terminal application can do by
leaving the terminal alone: select text across what the program drew and have it copied; keep that selection when the
content scrolls; click a component to act on it (open or fold a thinking block, list the runners behind a count); and
show images and long code without cluttering what someone is trying to read. They said these belong in TerminalKit, that
ask decides when they apply, and that the whole needs study across ask before it is built.

What TerminalKit has today, read from the source on 2026-10-20 and not run:

- **Mouse input exists and is unused above the decoder.** `MouseDecoder` decodes SGR 1006 and 1016 (cell and pixel
  coordinates, press, release, drag). `InputEvent.mouse` carries it, and `TerminalModes.mouse` enables reporting
  (`?1000`, `?1002`, `?1006`). Nothing maps a coordinate to what was drawn there.
- **A selection type exists, over a text buffer.** `TextSelection` holds an anchor and a head as `TextPosition(row, col)` and
  `extractText` slices by `Character` offset. It knows nothing of the screen or of scrolling. The kit can convert a display
  column to a character offset (`TextDisplayMetrics`), but selection does not use it.
- **The clipboard has both directions.** `EscapeSequences.setClipboard` writes through OSC 52, and `OSCClipboard.parse` reads
  the reply, including the empty reply kitty gives when it declines a read.
- **A kitty graphics encoder exists.** `GraphicsEncoder` chunks commands, and `PixelChrome` uses it for lines and bars
  under the cells. There is no image that belongs to content, no placement lifecycle under scrolling, and no fallback.

## Decision

1. **TerminalKit owns the mechanisms.** Hit regions and click events; a selection that spans what was drawn and is anchored
   in the content; clipboard output; a fold model with placeholders; image and long-code rendering. Each is a roadmap entry
   (0016 to 0019) and is designed and tested as a kit capability, in the benchmark and allocation regime of ADR-0016.
2. **The host owns the policy.** Whether a selection is copied on release, which blocks start folded, whether images are
   shown, folded or never drawn, how many lines make a code block long, and how many rows the input may take are the host's
   settings. The kit has defaults and none of them is a surprise: it never copies, hides or draws anything the host did not
   ask for. ask's settings are in its layered configuration (ask ADR-0044, roadmap 0051).
3. **A selection is anchored to content, not to the screen.** It names a position inside a block of content, so scrolling,
   resizing and re-wrapping do not lose it. This is the owner's requirement ("kept across a scroll"), and it rules out a
   design that stores screen rows and columns.
4. **Nothing that could be read is hidden without a placeholder.** Folding a block leaves a short line of text in its place,
   and there is always a way to unfold it. A long block cannot be drawn by the kit without a fold and its placeholder. This is
   the owner's requirement ("always providing a way to fold into a short placeholder text").

## Consequences

- **The kit must own selection once it takes the mouse.** On xterm-compatible terminals, enabling mouse reporting stops the
  terminal's own selection, usually with a modifier to get it back, and which modifier varies. That is known behaviour and has
  **not** been probed here. It is the price of this decision, and roadmap 0017 begins with the probe.
- **Layout has to say where text came from.** A selection anchored in content needs every drawn row to map back to a source
  range. `TextWrap` and `LayoutCache` (ADR-0025) already split text into rows, and what they would have to add is recorded in
  roadmap 0017.
- **A host that does not want the mouse can leave it off.** `TerminalModes.mouse` stays opt-in, so ask can offer a setting that
  gives the terminal its own selection back.

## What this does not decide

- How selection is drawn, how a copy treats a fold or an image inside it, whether a click always has a key equivalent, and
  whether hover is supported. Each is an open question in the roadmap entry it belongs to.
- The clipboard transport beyond OSC 52, size limits, and behaviour inside tmux and over ssh: unprobed (roadmap 0017).
- Anything about how the host lays out its own components. That is ask's roadmap 0051.
