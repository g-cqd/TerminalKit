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

## The cost, measured — and it is disqualifying for a blocking probe

Two queries on a PTY whose far end never replies:

    trial 0: answered=0+0  probe cost = 518.5 ms
    trial 1: answered=0+0  probe cost = 519.8 ms
    trial 2: answered=0+0  probe cost = 520.1 ms

A terminal that *does* answer costs microseconds — `poll` returns as soon as the reply lands. The entire
cost is the terminal's refusal to answer, and Terminal.app is exactly such a terminal.

**Against `ask`'s 25 ms cold-start budget, a blocking probe is roughly twenty times the entire budget.**
A caller that probes before its first frame cannot meet it on a terminal that ignores queries.

The first attempt at this measurement was invalid and worth recording: the PTY was left in canonical mode,
so it echoed the query bytes straight back, `select` returned on the echo, and the probe appeared to cost
0.01 ms. Only with the terminal in raw mode — no echo, as a real one runs — does the true cost appear.

## Consequences for adoption

- **`ask` must not block startup on this.** Either probe off the startup path and keep conservative
  defaults until answers arrive, or use a deadline short enough to fit the budget and accept that a
  loaded machine may produce false negatives. The first is the right answer; the second trades a
  correctness bug for latency.
- `defaultTimeout` therefore stays generous, because the type should not encode a policy that only one
  caller can choose. The cost is documented on it, because a caller who does not read it will blow a
  budget they never looked at.

## Follow-ups

- `TerminalCapabilities` still carries a single `supportsKittyGraphics` boolean. Splitting pixels from
  protocol is the obvious next step and belongs to whoever adopts it.
- Nothing here queries the keyboard protocol's *progressively-enhanced* mode, which is the fix for
  ESC-ambiguity latency and therefore a budget item rather than a capability one.
- A background probe needs a place to publish its answers. There is no seam for that yet.