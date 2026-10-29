---
status: not-started
blocked-by: []
date: 2026-10-29
---

# 0026 — AemiTerminal: a terminal emulator, headless first, then a macOS app, then iOS

Owner (2026-10-29): "we might want to create aemiterminal later, first as a fully compliant orchestratable entity and later as a macos
app, and later as an ios optimized one." Later, not now. (The name was once the plan for the terminal stack itself, ask ADR-0001; that stack
became TerminalKit, so the name is free.)

TerminalKit is the client side: it writes escape sequences to a terminal and decodes the terminal's replies and input. An emulator is the
other side: it hosts a program on a pseudo-terminal, parses what the program writes, keeps the screen, and answers queries. Much is shared
(the escape vocabulary, styles, cell widths, the Unicode tables now in AemiUnicode), which is why it belongs to this family.

## Phases

1. **A headless, orchestratable emulator.** A library and a process: spawn a program on a PTY, feed it keys and resizes, read its screen
   (cells, styles, cursor, modes, scrollback) and its replies, all from code. "Fully compliant": measured, not claimed, against `vttest`
   and `esctest` and the xterm control-sequence reference, with the gaps listed. Its first user is ask: its interface probes run on pyte
   today, which redraws some incremental updates wrongly (a reply missing until a resize forced a full redraw, ask 2026-10-29), so a probe
   cannot tell ask's bug from pyte's. An emulator the family trusts would end that, and would let agents drive terminal programs too.
2. **A macOS app** over the same core: a renderer (Core Text or Metal), selection, panes, the kitty keyboard and graphics protocols ask
   already speaks to.
3. **An iOS-optimised app**: touch input, a software keyboard with a key row, external keyboards, background limits, and a host to run
   programs on (SSH, or a local sandboxed shell where the platform allows).

## Before starting

- Decide what the screen model is shared with: TerminalKit's own frame model, or a new one the client side could also use for tests.
- Inventory what Atelier's KittyCode and TerminalKit already parse (both decode input escape sequences; neither parses program output as a
  terminal does).
- The conformance suite first, red: `vttest` and `esctest` cases as fixtures, failing, before the parser exists.
