---
status: accepted
date: 2026-10-19
supersedes: the `keyboardProtocolSupported` parameter in 0019
---

# 0020 — Kitty keyboard support is probed through the input stream, with device attributes as the sentinel

## Context

ADR-0019 pushed kitty keyboard flags only when the caller said the terminal supports them, and left
finding out to `TerminalProbe`. That probe waits out a 250 ms timeout per query when the terminal is
silent: 520 ms for two queries (ADR-0014), about twenty times ask's cold-start budget.

The kitty protocol documents another way to ask. Send `CSI ? u`, then `CSI c` (primary device
attributes). Every terminal answers device attributes, after any keyboard reply. So a device-attributes
reply with no keyboard reply before it is a definite "no", and nobody waits for a timeout.

## Measured (`CSI ? u CSI c` in one write, raw mode, five trials each)

| Terminal | Reply | Round trip |
|---|---|---|
| kitty | `CSI ? 0 u`, then `CSI ? 62;52; c` | 0.06–2.8 ms (19 ms on the first query in a new window) |
| ghostty | `CSI ? 0 u`, then `CSI ? 62;22;52 c` | 0.14–1.8 ms |
| wezterm (default config) | `CSI ? 65;4;6;18;22 c` only | 7.6–16 ms |
| Terminal.app | `CSI ? 1;2 c` only | 0.06–6.5 ms |

All four answer device attributes. That includes Terminal.app, which answers no DECRQM.

## Decision

- `TerminalSession(connection:modes:keyboardProtocol:)` takes `.supported`, `.unsupported` or `.probe`.
- With `.probe`, the entry write ends with `CSI ? u CSI c`, no flags are pushed, and nothing waits.
- The replies come through the application's input as `InputEvent.unknown`. The application passes every
  event to `session.observe(_:)`.
  - `observe` returns `true` for the session's own replies, which the caller drops.
  - On a keyboard reply it pushes the flags, so `leave()` will pop them. The application calls it where it
    writes frames, so the push never lands inside a frame.
- `InputSource.escapeIsUnambiguous` is now settable while reading. The application copies the session's
  value into it once the answer is in.
- A reply after `leave()` pushes nothing. If the session leaves before any reply, nothing is popped.

## Consequences

- Startup does not wait on the terminal. Until the answer arrives, Escape is read by the end-of-read
  heuristic. Each read sees the latest value.
- A terminal that answers neither query leaves the session asking forever. It pushes nothing and drops
  no input.
- `TerminalProbe` still blocks. It remains for callers that want every answer at once and can afford it.
