---
status: not-started
blocked-by: 
date: 2026-10-19
---

# 0013 — Unicode widths checked against real terminals

`UnicodeWidth` decides how many columns a grapheme takes. Terminals disagree on emoji sequences (ZWJ, VS16,
flags), and a mismatch shifts every following cell on the row.

## Probes

- Print a corpus of sequences on Kitty, Ghostty, iTerm2, Terminal.app and WezTerm, and read the cursor
  position after each (DSR), as ADR-0014 does for capabilities.
- Grapheme-cluster mode (`?2027`) where supported.

## What lands

A width table matched to what terminals actually do, with the measured disagreements documented and a policy
for each.
