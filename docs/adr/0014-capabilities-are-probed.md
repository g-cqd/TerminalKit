---
status: accepted
date: 2026-10-18
---

# 0014 — Capabilities are probed, and silence is not "unsupported"

## Context

`TerminalCapabilities.init(environment:size:)` decided whether the host spoke the kitty graphics
protocol by testing `KITTY_WINDOW_ID != nil || …`. `ask`'s roadmap 0003 has wanted active probing since
it was written, and `0014` finally supplied the measurement that made the guess falsifiable.

## The probe that refuted it

Running `ask`'s cell-pixel harness inside four real terminals, with the detection variables unset in the
launcher's own process so each terminal reported **its own** values:

| Terminal | pixels reported | cell | env guess |
|---|---|---|---|
| kitty | 1274×800 | 14×25 | True |
| ghostty | 1592×1192 | 16×34 | True |
| wezterm | 560×384 | 7×16 | True |
| Terminal.app | 560×336 | 7×14 | **False** |

So the guess is *usually* right. It is also wrong in ordinary use, and the harness produced the
counterexample itself: the first run reported Terminal.app as `True`. The cause was environment
inheritance — the agent session ran inside kitty, `KITTY_WINDOW_ID=4` was in its environment, every
terminal the launcher started inherited it, and TerminalKit's check is `KITTY_WINDOW_ID != nil || …`.

Separately confirmed by direct probe: **Terminal.app does not implement the kitty graphics protocol at
all.** Given the same transmit-and-place sequence, kitty consumed it and replied `ESC _ G i=1;OK ESC \`;
Terminal.app drew the APC introducer and the base64 payload as visible text. It cannot interpret APC, so
it cannot implement a protocol carried inside APC.

## Decision

1. **`TerminalProbe` asks, and reports only answers.** Cell pixel size comes from the connection's
   window size; synchronised output from DECRQM (`CSI ? 2026 $ p`); the kitty keyboard protocol from
   `CSI ? u`.
2. **Every probed field is optional, and `nil` means unknown.** A terminal that ignores a query has not
   said it lacks the feature. Collapsing silence into `false` is the conflation that produced the
   original bug, so the type is shaped to make it impossible to do by accident.
3. **Graphics support stays a hint, never a measurement.** No terminal defines a query for the kitty
   graphics protocol, so anything said about it is inference. It is kept apart in
   `TerminalCapabilities.hintedGraphicsSupport(environment:)` and never appears in a probed result —
   presenting a guess beside a measurement is how the two get confused.
4. **`readAvailable(until:into:)` added to `TerminalConnection`**, implemented on the POSIX connection
   with `poll`. A probe must wait for an answer without spinning and without occupying a thread; `poll`
   is the primitive for exactly that. The default implementation returns **nil, meaning "cannot
   answer"** — not `0`, because a probe that read `0` as "nothing there" would wait out its whole
   deadline on every query.

## Consequences

- `TerminalCapabilities` keeps its env-var initialiser for callers that want the cheap answer, now
  explicitly named as a hint. Removing it would break Atelier, which is mid-migration.
- `ask`'s roadmap `0003` can be closed against this, and `0006`'s teardown now has a measured capability
  story behind it.
- A caller wanting synchronised output can **know** rather than assume. `ask` currently emits DEC 2026
  unconditionally; a probed answer would let it skip the markers on a terminal that ignores them.

## Follow-ups

- The probe costs two round trips at startup, up to `defaultTimeout` each. That is charged against the
  cold-start budget and **has not been measured** — it must be, before the probe is adopted by `ask`.
- `TerminalCapabilities` still carries a single `supportsKittyGraphics` boolean. Splitting pixels from
  protocol is the obvious next step and belongs to whoever adopts it.
- Nothing here queries the keyboard protocol's *progressively-enhanced* mode, which is the fix for
  ESC-ambiguity latency and therefore a budget item rather than a capability one.