---
status: accepted
date: 2026-10-18
---

# 0002 — DECSTR does not reset DEC private modes

## Context

The reset ladder was documented as: selective cleanup, then **DECSTR, which "resets modes, cursor
and attributes"**, then RIS. The oracle test agreed. Byte-exact tests agreed. Both agreed with each
other, and both were wrong.

## The probe

A terminal can be asked what state it is in. **DECRQM** (`CSI ? Ps $ p`) makes an emulator answer on
stdin with `CSI ? Ps ; n $ y`, where `n` is 1 (set), 2 (reset) or 0 (unknown). That turns "does the
terminal really do this?" from a question about a model into a question about an emulator.

The verifier writes directly to `/dev/tty` in raw mode, turns every private mode on deliberately,
applies a tier, then queries the terminal. Each emulator was launched as `-e /bin/sh -c <verifier>`,
so no shell rc, no starship and no prompt could contribute escape sequences to the measurement.

| Terminal | DECRQM | Tier 1, selective | Tier 2, DECSTR |
|---|---|---|---|
| kitty 0.49.2 | partial — `?1015` unknown | **PASS** | `?1049` left set |
| ghostty | full | **PASS** | `?1049`, all mouse modes, `?2004` left set |
| wezterm | partial — `?1049` unknown | **PASS** | all mouse modes and `?2004` left set |
| Terminal.app | **none** | INCONCLUSIVE | INCONCLUSIVE |

## Findings

**1. The selective tier is verified.** It clears every mode that reports its state, on all three
capable emulators. This is real end-to-end confirmation of the tier that actually matters.

**2. DECSTR resets no DEC private mode anywhere.** Not one of them. This matches the specification —
a soft reset does not reset private modes — which means the documentation was wrong rather than the
emulators, and the oracle was wrong too.

**3. Terminal.app cannot be verified this way at all.** It answers no DECRQM query. The check is
inconclusive there, and is reported as inconclusive rather than quietly counted as a pass.

## Decision

- The oracle model no longer clears private modes on DECSTR, and the test that asserted the opposite
  is replaced by one asserting the **measured** behaviour.
- `TerminalResetTier.softReset` is documented as resetting cursor, rendition and margins only.
- The ladder's ordering is confirmed by evidence, not preference: because the first tier is the only
  non-destructive one that clears modes, and neither reset tier does it, tier 1 must always run.

## Consequences

- The ladder's value is now correctly stated. Its selling point is that **tier 1 does the work**, and
  RIS is the only thing that clears modes by force — at the price of the scrollback.
- Mode 25 (DECTCEM) is inverted, and bit the work twice: once in the oracle model, once in the first
  verifier, which reported a healthy terminal as a failure. Both are corrected, and the verifier now
  judges it explicitly.
- **Scrollback preservation remains unverified.** DECRQM reports modes, not history. That claim rests
  on the tiers emitting no `ESC c`, which is structural, and on the oracle. It is still an open
  question and should not be reported as measured.
- Terminal.app needs a different technique — observable screen state rather than mode queries — before
  it can be included.