---
status: accepted
date: 2026-10-20
---

# 0028 — What four terminals do with the mouse, the clipboard and graphics

## Context

ADR-0027 puts selection, clicks and folding in TerminalKit, and its consequences named three facts it had not probed: whether
the terminals take OSC 52, which key returns a terminal's own selection while the mouse is reported, and what images cost. This
records the probes, in the way ADR-0002 records the reset ladder, and the decisions the numbers force.

`Scripts/probe-interaction.sh` opens one window per terminal, one terminal at a time (OSC 52 uses the one system pasteboard), runs
`probe-interaction.py` inside it, and posts **real OS-level mouse events** into the window with `mouse-inject.swift`
(`CGEvent`, so the terminal's own reporting is what is measured). `analyze-interaction.py` decodes the result. macOS 27.2, on one
machine, on 2026-10-20; kitty, Ghostty and WezTerm as installed, and Terminal.app as shipped. The wheel events are synthetic
line-unit events, not a trackpad.

## What was measured

**OSC 52 write.** Payloads from 16 bytes to 1,000,000, each checked by reading the macOS pasteboard back and comparing the bytes.

| Terminal | Result |
|---|---|
| kitty | every size lands exactly, up to 1 MB; BEL-terminated too |
| Ghostty | every size lands exactly, up to 1 MB; BEL-terminated too |
| WezTerm | every size lands exactly, up to 1 MB, **except that the first write after a window opens is dropped** (4 of 4 observations, with payloads of 1 and 16 bytes first); later writes land in about 20 ms |
| Terminal.app | **nothing lands, at any size, with either terminator**: it ignores OSC 52 |

**Kitty graphics.** A query (`a=q`) answered with `OK`, and the cost of redrawing: delete every placement, place N images,
then a device-status request and the wait for its reply, so it times the terminal's parsing and not its drawing.

| Terminal | Query | 0 placements p50/p95 ms | 4 | 16 |
|---|---|---|---|---|
| kitty | yes | 0.94 / 3.03 | 1.28 / 3.05 | 2.62 / 3.08 |
| Ghostty | yes | 0.02 / 0.03 | 0.03 / 0.04 | 0.06 / 0.10 |
| WezTerm | yes | 3.89 / 4.00 | 3.94 / 4.10 | 4.00 / 4.16 |
| Terminal.app | **no** | 0.08 / 0.19 | 0.07 / 0.13 | 0.15 / 0.20 |

**Mouse reporting on** (`?1000 ?1002 ?1006`): which injected actions arrive, and with which modifier bits.

| Action | kitty | Ghostty | WezTerm | Terminal.app |
|---|---|---|---|---|
| click, drag (ten motion reports per drag), wheel | reported | reported | reported | reported |
| Shift + click or drag | **not reported** (terminal selects) | **not reported** | **not reported** | reported, with the shift bit |
| Option + click or drag | reported, alt bit | reported, alt bit | reported, **no alt bit** | reported, alt bit |
| Command + click or drag | not tried | not tried | not tried | reported, **no modifier bit** |
| fn + click or drag | not tried | not tried | not tried | **not reported** (terminal selects) |

So the key that returns a terminal's own selection is **Shift** in kitty, Ghostty and WezTerm, and **fn** in Terminal.app, where
Shift is reported to the program like any other modifier. WezTerm swallowed the first click on its unfocused window; the others
did not.

**Mouse reporting off**, alternate screen: the wheel becomes arrow keys, in a different number per terminal for the same injected
three-line scroll: kitty 15, Ghostty 9, WezTerm 3. Terminal.app sent down-arrows (18) and, from Option-click, 30 right-arrows
(its cursor-repositioning); its wheel-up is unexplained. With reporting on, the wheel is button 64 or 65 everywhere, and the same
scroll produced 3, 9, 1 and 3 reports in kitty, Ghostty, WezTerm and Terminal.app.

## Decision

1. **The clipboard has sinks, and OSC 52 is only one.** A `ClipboardSink` writes the text. OSC 52 is the default where it was
   measured to work (kitty, Ghostty, WezTerm). **Terminal.app needs the host's pasteboard** (ask runs `pbcopy`), so the kit
   identifies it (`TERM_PROGRAM` is `Apple_Terminal`) and says that OSC 52 will not arrive. A terminal the kit does not know gets
   both, which is harmless: the same text twice.
2. **The first OSC 52 write is sent twice** (a hypothesis to validate when it is built, with the probe as the test): WezTerm drops
   the first one, and writing the same text again is idempotent.
3. **Native selection keys are table-driven and shown to the user**: Shift, or fn in Terminal.app. ask can hint it in its status
   bar, and the setting that turns mouse reporting off (ADR-0044) gives the terminal's selection back everywhere.
4. **No feature depends on Option or Command.** WezTerm omits the alt bit and Terminal.app omits the Command bit, so plain, Option
   and Command clicks can be indistinguishable. Modifiers are passed on as reported and never the only way to do something.
5. **A wheel report is one step, and the host decides what a step scrolls.** Terminals send very different numbers of reports for
   the same gesture, so a fixed lines-per-report would scroll three to nine times too far in some of them. The host's step size is a
   setting, and measuring a real trackpad is open.
6. **Redrawing images each frame is affordable to parse.** Sixteen placements added under 2 ms in the worst case, so the prototype's
   pattern (delete, place again, skip what a popup covers) stands. Drawing cost is unmeasured. Terminal.app has no graphics, so its
   images are placeholders (roadmap 0018).

## Consequences

- Roadmap 0016, 0017 and 0018 each have their probe done; what they still owe is in their entries.
- A table of terminal identities lives in the kit, and a terminal missing from it gets the conservative behaviour in decision 1.
- The probe is reusable: a new terminal or a new version is one run of `probe-interaction.sh`.

## What this does not establish

- **tmux and ssh**, where mouse reporting and OSC 52 are filtered or translated, were not run.
- **Hover** (`?1003`), **pixel coordinates** (`?1016`), **clipboard reads**, and the **primary selection** were not tried. A kitty read
  prompts the user, so reading was left out on purpose.
- Command and fn were tried only in Terminal.app, and Shift, Option and fn on a physical trackpad not at all.
- Double and triple click counts, and the wheel's behaviour under acceleration.
- One machine and one version of each terminal. Drawing cost, as opposed to parsing cost, of images.
