---
status: accepted
date: 2026-10-19
---

# 0019 — Terminal modes belong to a session that enters and leaves them as a unit

## Context

TerminalKit had every mode sequence and no owner for them. Each application wrote its own enter and exit
sequences, and ask forgot bracketed paste, so a pasted newline pressed Enter (roadmap 0010). The Escape
key was read by a heuristic: a lone `ESC` at the end of a read is the key. A terminal write split after
the `ESC` byte turned an arrow key into Escape followed by text.

## Decision

- **`TerminalSession`** (TerminalKitInput) takes a `TerminalModes` value: alternate screen, hidden cursor,
  bracketed paste, focus reports, SGR mouse, kitty keyboard flags.
  - `enter()` takes raw mode, then writes every mode in **one write**. If the write fails it leaves
    before rethrowing.
  - `leave()` writes, in one write, `?2026l`, each mode off in **reverse** order, and tier 1 of the reset
    ladder, then restores `termios`. It is idempotent and safe from any thread, so the signal path and
    the normal path can both call it and the terminal sees one exit.
  - `run(on:modes:keyboardProtocolSupported:_:)` leaves however its body ends.
  - `TerminalModes.fullScreen` is ask's set: alternate screen, hidden cursor, bracketed paste, and
    disambiguated keys where supported.
- **Kitty keyboard flags are pushed only when the terminal answered the keyboard probe** (ADR-0014). The
  caller passes `keyboardProtocolSupported`; the session drops the flags otherwise.
- **With the disambiguate flag pushed, Escape is unambiguous.** `InputSource(connection:
  escapeIsUnambiguous:)` then keeps a trailing `ESC` pending for the next read instead of reading it as
  the key. Without it, the end-of-read heuristic stays.
- The terminal model now keeps one kitty keyboard stack per screen, so the oracle checks the pop order.

## Evidence

- Real terminals (`Scripts/verify-keyboard-protocol.sh`), on kitty and ghostty:
  - flags pushed on the alternate screen read 0 on the main screen;
  - they are still 1 on re-entering the alternate screen if never popped.
  So the pop must come before `?1049l`, and the model's per-screen stacks match both terminals.
- kitty sends the Escape key as `ESC [ 2 7 u` with the flag pushed. This was a real key, sent through
  remote control. ghostty has no key injection; not observed there.
- Red first: twenty failing expectations over the stubbed API. Green after.
- Negative control: popping after leaving the alternate screen fails three tests through the model.
- SIGTERM: a signal-thread `leave()` followed by the normal-path `leave()` restores every mode, with one
  restore of `termios`.

## Consequences

- Applications stop writing mode sequences themselves. ask adopts this with its next TerminalKit pin,
  replacing `StartupSequence` and `TerminalTeardown`.
- Leaving writes some bytes twice: the reverse sequence, then tier 1. That is about 100 bytes, once per
  exit, and tier 1 catches modes turned on outside the session.
- Deciding `keyboardProtocolSupported` costs a probe. When the terminal stays silent, that is the
  probe's timeout (ADR-0014). Caching or a non-blocking probe is the caller's choice; nothing here
  blocks on it.
