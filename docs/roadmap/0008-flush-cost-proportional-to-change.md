---
status: not-started
blocked-by: ["0006"]
date: 2026-10-19
---

# 0008 — Flush cost proportional to the change

## Evidence (ask's measurement, 2026-10-19, `RenderPipeline` over `MockTerminalConnection`)

A frame changing one cell costs **3 µs at 120×40 and 15 µs at 300×80**. The diff walks only dirty ranges,
so something else scales with the screen: dirty-range iteration, adoption into the front buffer, or the
signposts.

## What lands

- Find the O(screen) part with the 0006 suite and a profile.
- Remove it, so a one-cell frame costs the same at every size.
- Keep ADR-0016's zero-allocation ceiling.
