---
status: done
blocked-by: 
date: 2026-10-19
---

# 0010 — Terminal modes entered and left as one unit

Apps choose modes one escape sequence at a time. ask forgot one: its interactive screen never enabled
bracketed paste (`?2004`), so a multi-line paste arrived as typed keys and each newline pressed Enter.
TerminalKit has the sequences (`enableBracketedPaste`, `pushKeyboardMode`, `enableFocusEvents`, mouse modes)
but no owner for them.

## What lands

- A `TerminalSession` (name to be settled) that takes the modes an app wants:
  - alternate screen, cursor, bracketed paste, Kitty keyboard flags, focus, mouse, synchronised output;
  - enters them in one write;
  - leaves them in the reverse order on every exit path, the reset ladder included.
- **Kitty keyboard disambiguation** where the terminal supports it (probed, ADR-0014), so Escape is
  unambiguous without the end-of-read heuristic. The heuristic stays the fallback.
- Tests that every mode entered is left, on normal exit, a thrown error, and SIGTERM.

## Done (2026-10-19)

`TerminalSession` and `TerminalModes` in TerminalKitInput; ADR-0019. Entered in one write and left in one
write, with the reverse order checked by a terminal model that keeps one keyboard stack per screen, as kitty
and ghostty do. Kitty disambiguation is pushed when probed, and `InputSource(escapeIsUnambiguous:)` drops
the end-of-read heuristic then. Tests cover a normal return, a thrown error, a failed entry and SIGTERM.
