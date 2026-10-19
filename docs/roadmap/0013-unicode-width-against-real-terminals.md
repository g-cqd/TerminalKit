---
status: done
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

## Done (2026-10-19)

ADR-0024. Probed 54 graphemes on kitty, ghostty, wezterm and Terminal.app:
- TerminalKit agreed with at least one terminal on all but one, a Thai combining vowel, which is fixed;
- the terminals disagree with each other on 17, and a cursor move after each makes the row land the same on
  all four;
- width is a table lookup: CJK 141 → 11 ns, emoji 72 → 12.

iTerm2 was not installed. `?2027` is no policy: one terminal lacks it, one has it reset, one always has it on.
