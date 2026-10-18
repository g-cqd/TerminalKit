---
status: accepted
date: 2026-10-18
---

# 0004 — Screen and scrollback preservation, measured

## Context

[ADR-0002](0002-decstr-does-not-reset-private-modes.md) settled the mode question and left one
explicitly open: DECRQM reports modes, not history, so whether tiers 1 and 2 spare the scrollback was
still resting on the structural argument that neither emits `ESC c`.

That argument is not a measurement, and the project does not accept arguments where measurements
belong.

## The probes

The verifier now also leaves **sentinels** on the screen and records **cursor position via DSR** (`CSI
6 n`), the one screen query every terminal answers — including Terminal.app, which answers no DECRQM at
all. A second script reads each terminal's screen back from *outside*, so the terminal's report and
what it actually rendered are checked separately.

| Terminal | Tier 1 modes | Screen kept after T1 | Screen kept after T2 | History kept |
|---|---|---|---|---|
| kitty 0.49.2 | PASS | **yes** | **yes** | **yes** — 100 `FILLER-0xx` lines in `--extent=all` |
| ghostty | PASS | no reader | no reader | no reader |
| wezterm | PASS | **yes** | **yes** | not readable |
| Terminal.app | no DECRQM | **yes** | **yes** | not readable |

Each terminal was launched as `-e /bin/sh -c`, so no shell configuration contributed escape sequences.

## Findings

**1. Both non-destructive tiers preserve the screen.** Confirmed on kitty, wezterm and Terminal.app.
`SENTINEL-AFTER-TIER1-KEEP` and `SENTINEL-AFTER-TIER2-KEEP` were both still rendered afterwards.

**2. kitty preserves its history too.** After both tiers, 100 filler lines were still retrievable from
`--extent=all`. This is the scrollback claim that was previously only structural.

**3. Terminal.app is verifiable for screen state** through AppleScript, even though it answers no
DECRQM. Its *mode* state therefore remains unverifiable by this technique — a terminal limitation,
reported as inconclusive rather than counted as a pass.

**4. ghostty exposes no text-extraction API**, so it is verifiable for modes only.

## Three harness bugs found by building it

- **A stale alternate screen.** The screen probes initially ran inside the alt screen left over from
  the mode probes, so kitty and ghostty reported the cursor jumping home after tier 1 — which reads as
  "the tier cleared the screen" and was false. Fixed by resetting to a clean main screen first.
- **The terminals exited before the reader ran**, so every reader found nothing. Fixed by holding each
  terminal open after the verifier exits.
- **Terminal.app stopped launching** under three levels of nested shell quoting inside an AppleScript
  string. Fixed by writing a script file and running it by path.

## Consequences

- The ladder's central claim is now measured rather than argued: **tier 1 preserves screen and, on
  kitty, history; tier 2 preserves the screen; tier 3 is the only destructive one.**
- `Scripts/verify-screen-against-emulators.sh` is committed so anyone can re-run the matrix.
- Remaining gaps are **capability gaps, not design gaps**, and are stated as such: ghostty has no
  reader, and history is not extractable from wezterm or Terminal.app through the interfaces used here.
  Closing them would mean a different technique per terminal, not a change to the ladder.