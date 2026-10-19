---
status: done
blocked-by: ["0006"]
date: 2026-10-19
---

# 0011 — Scroll regions for streaming text

A bottom-aligned transcript shifts every visible row when a line arrives. ask measured 494 bytes per streamed
line at 120×40 and 1,048 at 300×80, re-sending each row's changed cells. `RenderPipeline.scrollHint`
(DECSTBM plus scroll) can move the region in a few bytes and leave only the new line to draw.

## What lands

- Measured bytes and time per streamed line, with and without the hint.
- An API that makes the hint easy to apply from a layout: "this region scrolled by n".
- A probe on real terminals that scroll regions render correctly inside synchronised output.

## Done (2026-10-19)

ADR-0022. `RenderPipeline.scrollRegion` detects the shift itself, and the diff writes short unchanged gaps
instead of jumping them. A streamed line costs 151 bytes instead of 413 at 120×40, and 301 instead of 817
at 300×80, for 7 to 35 µs more CPU. Checked on kitty, wezterm and Terminal.app by
`Scripts/verify-scroll-region.sh`.
