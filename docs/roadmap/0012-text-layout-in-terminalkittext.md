---
status: not-started
blocked-by: 
date: 2026-10-19
---

# 0012 — Text layout by display width belongs in TerminalKitText

ask wrote `TextWrap` (word-wrap by display width, wide characters as two columns), and its composer caches
wrapped lines per item revision. Neither is specific to ask, and both are the kind of tool any terminal app
rewrites. Per ADR-0007 (generic tools belong in the shared package), promote:
- wrapping;
- a cached, revision-keyed layout of a growing document.

Measure, while promoting, how much grapheme iteration costs in wrapping. The same lesson as ask's 14 ms output
cap: walk bytes where graphemes are not needed.
