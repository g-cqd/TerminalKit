---
status: done
blocked-by: []
date: 2026-10-29
---

# 0021 — The terminal's page, its appearance, and the scroll rules, moved from ask

The owner: TerminalKit is critical, and its consolidation comes before AemiMarkdown is finished. ask wrote three things that belong to any host
of the kit, and Atelier would otherwise write them again.

## What moved

| Was in ask | Is in the kit | Where |
| --- | --- | --- |
| `ScreenTheme.Page`: WCAG luminance and contrast, the missing-foreground rule, mixing a tint from the page, the secondary-text grey | `TerminalPage` | `TerminalKitCodecs`, beside `ColorRGB` and `OSCPalette` |
| `TerminalColours`: the OSC 10 and 11 query without the DA1 terminator, answer recognition, reading the page from the foreground and background, the off-loop write | `PageFollower` and `OSCPalette.pageQuery` | `TerminalKitInput` and `TerminalKitCodecs` |
| `TerminalColours.watchAppearance` and `askAgain`: the macOS appearance notification and the two re-asks (150 ms, 1 s) | `SystemAppearance` (`Watch` token, `askAgain` over an injectable clock) | `TerminalKitInput` |
| Three copies of the scroll rules: the wheel, the Page keys, the fold that moves the reader | `ScrollPosition` | `TerminalKitText`, next to `ScrollAnchor` |

ask keeps what is its own: the kind-specific shares (input .05/.06, user .12 blue, pending .06/.065, success .11/.10, failure .11, system .11
purple), the choice of which block is which colour, and `ScreenOptions.appearance`.

## Tests

Deterministic, no sleeping: `TerminalPageTests` (6, the real profiles from ask's tests), `PageFollowerTests` (8: query bytes, answers in both
terminators, non-answers, the write through the mock connection, re-asking under `TestClock`, and a real distributed notification reaching a
`Watch`, three runs in a row), `ScrollPositionTests` (7).

## Not done here

`PageFollower` knows no key events; the host decides what an answer means for its screen. Linux has no system appearance notification
(roadmap 0024). Contrast is WCAG 2; a perceptual model (APCA) was not weighed.
