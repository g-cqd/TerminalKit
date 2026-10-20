---
status: not-started
blocked-by: ["0016"]
date: 2026-10-20
decision: ADR-0027
---

# 0018 — Foldable content: images and long code, always with a placeholder

Render images and long code blocks so that each can be folded into a short line of text and unfolded again, so they never
bury what someone is trying to read. When to show them is the host's setting (ADR-0027).

## What exists

`GraphicsEncoder` and `GraphicsCommand` (kitty graphics, chunked), and `PixelChrome`, which draws lines and bars under cells with
them. The ask UI prototype (ask roadmap 0015) already proved the placement pattern on thin images: delete every placement each
frame and place again, skip a placement that falls under a popup, crop a tall one with the protocol's source rectangle.

## What is missing

- **An image that belongs to content**: transmitted once and cached by identity, placed at a block's cells, cropped at the
  viewport's edges, sized to the cells it is given (the cell size is the window size's pixel fields over its cells, `TerminalCapabilities.cellPixelSize`,
  measured in ask roadmap 0014), and released when the
  block is gone. Its cost under scrolling is unmeasured.
- **A fallback where there is no graphics protocol** (Terminal.app has none): the placeholder text, so the content is still there
  to be reached.
- **A fold model.** A foldable block has a state (shown or folded), a placeholder the host supplies (for example the kind and
  size, `image 1280x720`, or `swift, 142 lines`), and a layout in both states. The API makes it impossible to draw a block the kit
  considers long without one (ADR-0027, point 4).
- **Long code**: when a block is long is the host's number; how a shown block scrolls sideways or wraps; highlighting is out of
  scope here.

## Open questions

- Folded and shown blocks change the height of everything below them: which line stays under the pointer when a block above the
  viewport is toggled? ask has the same rule for thinking blocks ("expanding must not move the reader", ask diary 35), and the
  kit should own the answer.
- A selection or a search that touches a folded block (roadmap 0017).
- Memory for transmitted images, and what to do with an image larger than the terminal.
- Animated images, and images inside the input: out of scope until asked for.

## Probe (done, ADR-0028)

Kitty graphics is answered by kitty, Ghostty and WezTerm, and **not by Terminal.app**, which gets the placeholder. Redrawing is cheap
to parse: 16 placements per frame added under 2 ms in the worst case (kitty p50 0.94 to 2.62 ms; Ghostty 0.02 to 0.06; WezTerm
3.89 to 4.00). **Drawing** cost, behaviour under a real scroll, and an image taller than the screen are still unmeasured.

Images are also **rare in agent transcripts**: 0.06% of Claude Code and Codex messages and 0.58% of Pi's carry one (ask's
`probe-ui-content-sizes.py`, counts only). That puts them last in the build order, behind code and thinking.

## Done when

A fold API and a content image with tests for both states, cropping and release; a fallback test with graphics off; a benchmark
of a scroll over images; a real-terminal check in at least kitty.
