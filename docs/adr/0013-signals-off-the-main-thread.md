---
status: superseded
superseded-by: ADR-0015
date: 2026-10-18
---

# 0013 — Signals are delivered off the main thread, and the handler reports which one fired

> **Superseded by ADR-0015.** Off-main delivery was necessary but insufficient: the Swift callback
> still took a mutex in signal context. ADR-0015 also corrects descriptor lifetime and stop ownership.

## Context

`SignalHandler` delivered `SIGWINCH`, `SIGINT` and `SIGTERM` through an `AsyncStream` fed by
`DispatchSource.makeSignalSource(signal:queue:)` — with `.main` as the queue.

Measured on a PTY against a running `ask`, which is the case that matters:

| Configuration | Result on `SIGTERM` |
|---|---|
| no handler | killed by `SIGTERM` — the process dies, the terminal is **not** restored |
| `SignalHandler` installed | **ignores `SIGTERM`** — still running after 4 s, needs `SIGKILL` |

**REFUTED, and worse than the bug.** A terminal program blocks its main thread in `read(into:)`,
so the main queue never turns, the continuation never yields, and the process stops responding to
`SIGTERM` entirely. A handler that appears installed and does nothing is worse than no handler,
because it reads as handled.

Two secondary defects came with it:

- `onShutdown` took no argument, so a caller could not tell `SIGINT` from `SIGTERM` and could not
  produce the shell-conventional `128 + signo` exit status.
- There was no way to stop a handler, so the process-global pipe could never be released.

## The probes

**Probe 1 — does the mechanism work at all?** Compiled the self-pipe design standalone, outside any
test harness, and sent the process its own `SIGTERM`.

**CONFIRMED.** The process survived, and the handler received `15` — the signal it was sent.

This was the probe that mattered: at that point the suspicion had moved from "TerminalKit's handler
is wrong" to "my test harness is wrong", and only a probe outside the harness could separate them.

**Probe 2 — do the tests actually catch the defect?** Broke the drain so the resize branch never
fires, then ran the suite.

**CONFIRMED.** `SIGWINCH reaches the resize closure` failed with a named
`AsyncEventProbeTimeoutError` — not a hang, not a silent pass.

An earlier break produced *zero* failures, because it was a compile error rather than a behavioural
change. That is the fourth time this month a "probe" turned out to be incapable of failing, and the
reason every guard in this repository is broken on purpose before it is trusted.

## Decision

1. **Deliver through a self-pipe, drained by a dedicated thread.** A `sigaction` handler does the
   least async-signal-safe thing possible — one `write` of one byte — and returns. A
   `Foundation.Thread` blocks in `read` on the other end. Neither the main thread nor a cooperative
   pool thread is involved, so a blocked read cannot starve delivery.
2. **`onShutdown` receives the signal number.**
3. **`start()` throws** if another handler holds the process-global pipe, and **`stop()`** releases it,
   restores `SIG_DFL`, and lets the drain thread exit.
4. **`SA_RESTART` is deliberately not set**, so a blocked `read` returns `EINTR` rather than hanging.

## Why a `Thread` and not a `Task`

Parking a Swift task on a blocking `read` costs the cooperative pool one of its threads for the
process's lifetime. This package is consumed by programs whose budgets are measured in single-digit
milliseconds, and the alternative — `DispatchQueue` — is banned across the ecosystem. A dedicated
`Thread` with a 128 KiB stack is the primitive that costs what it actually uses.

## Why the test deadline is real rather than injected

`AsyncEventProbe` accepts an injectable clock, and under a `TestClock` the wait ends **only** when the
event arrives. That is maximum determinism — and a hang forever if delivery ever breaks again.

That trade is wrong here. A hang in CI is indistinguishable from a busy machine and diagnoses nothing;
a real, generous deadline fails with a named error instead. So the tests use the `ContinuousClock`
convenience overload with a five-second deadline that never fires in practice, because the wait is
event-driven and ends microseconds after the signal.

The suite runs in **0.001 s**, so there is nothing to flake.

## Consequences

- **Breaking change:** `onShutdown` gains a parameter, `start()` throws and returns `Void` instead of
  a `Task`. No consumer in the ecosystem other than `ask`, which has not shipped this wiring.
- `ask`'s `SignalShutdown` can now be wired — the blocker on its roadmap `0006` is lifted, subject to
  that repository re-running its own probe.
- One pipe, one drain thread, per process. Two live handlers conflict loudly rather than corrupting
  the first one.
- The `SIGWINCH`-first ordering in the tests is a safety measure, not ceremony: `SIGWINCH`'s default
  disposition is *ignore*, so it proves delivery is live before anything with a lethal default action
  is sent at the test process itself.

## Follow-ups

- `SIGHUP` is not handled. That is arguably correct — `SIGHUP` means the terminal closed, so there is
  nothing left to restore — and it is stated rather than assumed.
- The `read` call is not interrupted-safe against a partial byte, though a one-byte write cannot tear
  in practice.