---
status: accepted
date: 2026-10-19
---

# 0023 — Input is read on a thread of its own, waiting in `poll` beside a wake-up pipe

## Context

`InputSource.start()` read the terminal inside a `Task`. Its blocking `read()` held one of the cooperative
pool's threads for the whole session (roadmap 0009). Measured with `Benchmarks/Probes/InputPoolProbe`,
ten cores, median of 15:

| | Batch of 10 CPU-bound tasks |
|---|---|
| Alone | 15.6 ms |
| While an InputSource reads an idle PTY | 23.4 ms |

Worse, `stop()` could not end a read that was waiting. A stopped source kept its pool thread until the
next byte arrived. The probe's first version created a source per trial and never sent it a byte: the
batch slowed trial by trial (24, 36, 47, 60, 114 ms), and the pool ran out by the tenth.

## Decision

- **A dedicated `Thread`** named `TerminalKit.input`, as `SignalHandler` already has. It waits in `poll`
  on the terminal's descriptor and on a wake-up pipe, then reads, routes and yields as before.
- **Stopping wakes it.** `stop()`, cancelling the task `start()` returns, or a consumer that stops
  iterating `events` all set a flag and write one byte to the pipe. The thread closes the pipe as it
  exits, under the same lock as the wake, so a late wake writes nothing.
- **`TerminalConnection.pollableFileDescriptor`**, a new requirement with a default of nil. The POSIX
  connection returns its read descriptor. A connection without one, such as the mock, is read directly.
- **`start()` still returns a `Task<Void, Never>`.** It now ends when the thread does, so callers and
  tests are unchanged.

## Measured after

| | Batch of 10 CPU-bound tasks |
|---|---|
| Alone | 15.5 ms |
| While an InputSource reads an idle PTY | 15.7 ms |

- Keystroke to event, with the pool saturated by twenty busy tasks and the consumer on the main thread:
  0.02 ms before and after. The reader never needed the pool to deliver; it needed the pool to exist.

## Evidence

- **Red:**
  - `reads run on the input thread, not the cooperative pool` failed: the name was not
    `TerminalKit.input`.
  - `stopping ends a read that is still waiting for input` hung on the old code. `sample` showed it
    blocked in `read` under `InputSource.start()`; the run was killed by an external timer.
- **Green after.**
- **A mistake of mine:** the first version of the stop test wrote a key to a PTY in canonical mode. The
  key never arrived, in either design, so the test hung for the wrong reason. The PTY is now raw, as a
  full-screen program runs it.
