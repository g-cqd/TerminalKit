---
status: accepted
date: 2026-10-19
---

# 0018 — Raw mode never waits on output, and tier 1 ends synchronized output and focus reporting

## Context

ask compared TerminalKit with rst (rauchg/rst at 5a2d488, a two-millisecond `reset`) and listed what rst
does that TerminalKit does not. ask's PTY probes had twice hung in TerminalKit's restore. Each item was
probed here before adoption (`Scripts/probe-termios-waits.py`, diary 2026-10-19-03).

## Measured (macOS 27.2, a fresh PTY per case, 100 bytes queued, a 2 s timer as "forever")

| Change | Output stopped (`TCOOFF`) | Emulator not reading |
|---|---|---|
| `TCSAFLUSH` (what TerminalKit used) | waits | waits |
| `TCSADRAIN` | waits | — |
| `tcflow(TCOON)`, then `TCSAFLUSH` (what rst does) | returns | **waits** |
| `TCSANOW` | returns | returns |

- `TCSANOW` keeps unread input; `TCSANOW` then `tcflush(TCIFLUSH)` discards it as `TCSAFLUSH` does.
- Output queued before a `TCSANOW` change is not reprocessed under the new output flags.
- A stop survives a `TCSANOW` restore: the shell after the program stays frozen until `TCOON`.
- A background job that calls `tcsetattr` is stopped by `SIGTTOU`.

## Decision

- **Entering and leaving raw mode** both run `tcflow(TCOON)`, `tcsetattr(TCSANOW)`, `tcflush(TCIFLUSH)`.
  Neither waits on output, a stop is lifted (Ctrl-Q is a key in raw mode, so nothing else would lift
  it), and typeahead is still discarded.
- **Tier 1** gains `?2026l` first (inside an open synchronized update the terminal holds what follows)
  and `?1004l` (focus reports would reach the shell as `ESC [ I` and `ESC [ O`).
- **Not adopted from rst, each with its reason:**
  - *Refusing to run from a background job.* That is a reset tool's rule. A full-screen program
    started with `&` is stopped by `SIGTTOU` until the user brings it to the foreground, which is
    ordinary job control and what the user expects.
  - *Repairing disabled control characters.* TerminalKit restores the `termios` it saved, not a
    constructed default, so it never disables one.
  - *`?7h` and `4l`.* rst sends them only in its fallback after RIS. Nothing in TerminalKit or ask turns
    wraparound off or insert mode on, so tier 1 would be clearing state that nothing sets.

## Evidence that the decision holds

- Red: three PTY tests (`TerminalRestoreTests`) blocked; `sample` showed each in `tcsetattr`, under
  `restoreMode` or `enterRawMode`. Green after the change. Negative controls: dropping `tcflush` fails the
  typeahead test; dropping `tcflow` fails both stopped-output tests.
- Real emulators (`Scripts/verify-reset-ladder.py`): tier 1 resets `?1004` and `?2026` on kitty, ghostty
  and wezterm. A control queried straight after `?2026h` reads set on kitty and ghostty, so their reset
  is the tier's doing and not the update's timeout. wezterm does not answer during an open update:
  inconclusive there.
