---
status: not-started
blocked-by: []
date: 2026-10-28
---

# 0020 — What ask needs from the kit

The owner, 2026-10-28: TerminalKit is critical to ask, so its roadmap is addressed with ask's. This entry gathers what ask's
roadmap asks of the kit, in one place, so the kit's work is ordered by its consumer. Entries 0016 to 0019 stay the owners of
their own "Still owed" lists; this one adds what they do not carry.

## Wanted by ask, with the ask entry that waits

| # | Need | State in the kit (read 2026-10-28) | ask entry |
| --- | --- | --- | --- |
| 1 | Key chords with the Super (Command) modifier reach the host as `Super`+key, not as text | `KeyModifiers.super` exists (`TerminalKitCodecs/Types.swift`). Whether `SequenceRouter` decodes a CSI-u `super` chord and drops it, or emits the letter too, is **unprobed**. | 0082 |
| 2 | The real terminal background and palette, delivered to the host's session (OSC 10/11/4 replies) | `OSCPalette` exists in `TerminalKitCodecs`; delivery of the replies to a session is not wired. | 0074 (tint) |
| 3 | Pixel rules and pixel strokes where graphics exist | Not built; waits on the probe split into pixel size and graphics protocol. | 0074, 0014, 0003 |
| 4 | The probe off the startup path, and pixel versus protocol as two answers | Probe built (ADR-0014). It conflates the two in `supportsPixelChrome`. A blocking probe costs 520 ms. | 0003 |
| 5 | Images placed at a block's cells, cached by identity, cropped, with a placeholder where no protocol | Roadmap 0018; probed for parse cost only. | 0084 (display is optional) |
| 6 | The keyboard protocol decision (ESC latency, unambiguous Esc and Ctrl-C) | Probe reads `CSI ? u`; enabling it is undecided. | 0083, 0064 |
| 7 | OSC 8 hyperlinks: hover and click checked in Ghostty, WezTerm, iTerm2, Terminal.app | Built (`Style.link`, e0b13ab); only kitty observed, and without a hover check. | 0075, 0065 |
| 8 | Mouse regions used by a host; tmux and ssh | 0016: nothing in the kit consumes the recognizer; tmux and ssh unprobed. | 0051 |
| 9 | Selection painted without redrawing unchanged rows; across folds | 0017 owed. | 0051 |
| 10 | Wrapped-row input viewport, wheel and click inside the input | 0019 owed (ask drives its own map today). | 0051, 0049 |

## Work

1. Probe item 1 first, because it is a defect the owner sees every day: feed the kit the bytes a terminal sends for Command+C,
   Command+X and Command+V (kitty with the keyboard protocol on, Ghostty, Terminal.app) and record what `SequenceRouter` returns.
   Fix in the kit if the chord is dropped or doubled there; otherwise the fix is in ask (0082).
2. Item 2, then item 4: they unblock the pixel work and the tint.
3. Close 0016 to 0019 against ask's use of them, in the order ask's roadmap needs (0051).
4. A real-terminal pass for item 7 (needs the owner at four terminals).

## Done when

Each row above has either a probe-backed verdict recorded in the kit's diary or a built and tested change, and the ask entry that
waited names the result.

## Update (2026-10-28, from ask 0095)

- Make the forward Delete key (and Insert) public in `Key` (`delete = 57349`, `insert = 57348`). `FunctionalKeyCode` is private to
  `SequenceRouter`, so ask names 57349 itself (`PromptEditor.forwardDelete`).

## Status (2026-10-29)

Rows 2 and 10 are done through roadmap 0021: the terminal's palette is delivered to a host (`PageFollower`), mixed into a page's tints and
secondary text (`TerminalPage`), and re-asked when the system appearance changes (`SystemAppearance`); ask's own copies are deleted. Row 7
and row 8 are partly done in ask (see 0016). Rows 1, 3, 4, 5 and 6 are unchanged: 1 and 6 are unprobed and need a real terminal, 3 and 5 wait
for graphics. Entries 0016 to 0019 carry a status paragraph dated today. New work this consolidation opened: 0021 (done), 0022 (the markdown
renderer), 0023 (row windows), 0024 (Linux), 0025 (event-driven).
