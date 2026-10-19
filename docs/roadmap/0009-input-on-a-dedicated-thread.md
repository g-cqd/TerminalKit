---
status: done
blocked-by: ["0006"]
date: 2026-10-19
---

# 0009 — Input reads on a dedicated thread, not a cooperative one

`InputSource.start()` runs its blocking `read()` inside a `Task`, so it holds one of the Swift concurrency
pool's few threads for the whole session (read from the code, 2026-10-19). `SignalHandler` already uses a
dedicated `Thread` for its blocking reads. Input should do the same, or wait on readiness (kqueue), so an
app's own concurrency never loses a pool thread to the terminal.

## Measure

Keystroke-to-event latency before and after, under a loaded pool (many concurrent tasks), with the 0006 suite
and a PTY probe.

## Done (2026-10-19)

ADR-0023. Reading moved to a `TerminalKit.input` thread that waits in `poll` beside a wake-up pipe:
- a CPU-bound batch beside a reading source takes 15.7 ms instead of 23.4 (15.5 alone);
- `stop()` now ends a source that is waiting for input.
