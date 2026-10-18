---
status: not-started
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
