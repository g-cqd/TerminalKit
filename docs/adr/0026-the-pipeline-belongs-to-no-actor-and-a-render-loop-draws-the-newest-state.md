---
status: accepted
date: 2026-10-19
---

# 0026 — The pipeline belongs to no actor, and a render loop draws the newest state on its own thread

## Context

`RenderPipeline` was `@MainActor`, so ask's screen loop had to run on the main actor: one loop applied each
event, composed and flushed, in that order. Input is read on its own thread (ADR-0023), but its *handling*
waited behind every frame (roadmap 0014). The question, set by the user: which ownership keeps input from
blocking and keeps rendering, stress-tested against the alternatives.

## The stress test

`Benchmarks/Probes/IsolationProbe` runs four designs through the same frames, at 120×40, 3 s per run, with a
thread injecting a keystroke every 50 ms and another streaming lines at a fixed rate. The composer can be
made to cost more (0.1 ms is ask's; 2 ms stands for syntax highlighting or markdown), to spike (40 ms every
100 lines), and the main actor can be kept 50 % busy. Times in milliseconds, p50 / p99.

- **A**: main actor, one frame per event (ask today).
- **A′**: main actor, every event waiting is applied, then one frame.
- **B**: events applied off the main actor; a thread draws the newest state, skipping the ones it was too slow for.
- **C**: B as shipped, `RenderLoop`.

| Scenario | Design | Key handled | Key shown | Frames | Unread at end |
|---|---|---|---|---|---|
| Idle | A / A′ / B / C | 0.03–0.05 / p99 ≤ 2 | 0.06–0.11 | 54 | 0 |
| 5000 lines/s, cheap composer | all four | 0.01 / 0.04 | 0.02–0.03 | 15,050 | 0 |
| 500 lines/s, **2 ms composer** | A | **67.5 / 129** | 69.5 / 131 | 1,487 | 61 |
| | A′ | 1.1 / 2.0 | 3.1 / 4.1 | 1,478 | 1 |
| | B, C | **0.01** / 0.06, 0.89 | 2.9–3.1 / 4.0–4.2 | 1,491, 1,476 | 0 |
| 5000 lines/s, **2 ms composer** | A | **1,949 / 2,452** | 1,951 / 2,454 | 1,490 | **3,610** |
| | A′ | 1.2 / 2.0 | 3.2 / 4.0 | 1,479 | 1 |
| | B, C | **0.01** / 0.01, 0.04 | 3.0–3.3 / 4.0 | 1,492 | 0 |
| 500 lines/s, cheap composer, **main actor 50 % busy** | A, A′ | 0.02 / **5.0** | 0.03 / 5.0 | 1,554, 1,390 | 0 |
| | B, C | 0.01 / **0.05** | 0.03 / 0.06–0.11 | 1,552, 1,553 | 0 |
| 500 lines/s, 2 ms composer, **main actor 50 % busy** | A | **173 / 261** | 175 / 263 | 1,420 | 51 |
| | A′ | 2.9 / 7.0 | 5.0 / 9.0 | **888** | 1 |
| | B, C | **0.01 / 0.03** | 3.0–3.2 / 4.0 | **1,491** | 0 |
| A **40 ms frame** every 100 lines | A, A′ | 0.02 / **37, 38** | 0.13 / 37, 40 | 1,553, 1,258 | 0 |
| | B, C | 0.01 / **0.02, 0.03** | 0.13 / 31, 35 | 1,260, 1,257 | 0 |

What the numbers say:

1. **One frame per event collapses once a frame costs more than the gap between events.** At 2 ms a frame
   and 5,000 lines a second, a keystroke waited two seconds and 3,610 events were still queued when the run
   ended. Nothing in ask costs 2 ms today (its composer takes 0.1 ms), but anything that grows the composer
   will.
2. **Drawing the newest state, not every one, removes that.** A′ fixes it on the main actor, so most of the
   win is the coalescing, not the thread.
3. **What the thread adds is input that is never behind a frame.** A′ handles a key after the frame in flight
   (1–5 ms); B and C in 0.01 ms, whatever the frame costs. Through a 40 ms frame spike the keystroke is still
   handled in 0.02 ms where A and A′ take 37 ms. (What is shown cannot beat the frame being drawn; both show
   it after the spike.)
4. **And rendering that the main actor cannot starve.** With the main actor half busy, A′ drew 888 frames to
   B's 1,491 and handled keys at p99 5–7 ms to B's 0.03–0.05.
5. **When nothing is loaded the three are the same**, within noise: idle, 500 and 5,000 lines a second with
   the cheap composer. The thread costs no latency at ask's real load.

## Decision

- **`RenderPipeline` belongs to no actor** and is not `Sendable`: whoever owns it draws into it. A thread or
  an actor of the app's own may.
- **`RenderLoop<Composer: FrameComposer>`** owns a pipeline on a `TerminalKit.render` thread. A producer calls
  `submit(_:)`, which returns at once; the newest state replaces any not yet drawn. `resize(columns:rows:)` and
  `redraw()` make the next frame a full one, from the last state if no newer arrives. `finish()` draws the
  last state and stops (async); `halt()` stops without drawing and returns once the thread has, for a
  shutdown path that must write to the terminal next. A write error ends the loop and is in `failure`.
- **A composer is a `Sendable` value** the loop takes, with `compose(_:into:)` called on the render thread.
  What a frame shows is a `Sendable` state snapshot.
- **Signposts are opt-in** (`signposts`, or `TERMINALKIT_SIGNPOSTS=1`). They allocate nothing but cost 0.46 µs a
  frame, more than a one-cell frame's own work: one-cell flush p50 0.79 → 0.33–0.38 µs without them, on all
  three sizes, and no other suite moved. `OSLog.signpostsEnabled` is true whether or not anything is watching
  (tried, no change), so it cannot gate them.

## Consequences

- The cost is a thread (a 512 KiB stack, one page touched), a snapshot of the state per frame, and the
  discipline that a composer reads only its state.
- Frames are skipped under load by design. A caller that must see every state (a recording) should not
  use a render loop.
- A signal-time restore must `halt()` the loop before `TerminalSession.leave()`, or a frame in flight could
  land after the terminal was restored.

## Evidence

- Red: `PipelineIsolationTests` did not compile (the pipeline was main-actor); `RenderLoopTests` hung against a
  stub (killed by an external timer), then passed. The probe's own first run showed the render thread
  stopping at the deadline with a state still waiting; it now stops when its events have.
- Tests: a frame runs on `TerminalKit.render`; a state submitted during a frame replaces the ones before it
  (`["one", "four"]`); `finish()` draws the last; a later submit is ignored; the second frame is a diff; a
  resize redraws at the new size; a failing connection ends the loop; `halt()` draws nothing more.

## Addendum: one writer at a time

A render thread writes frames while an event loop may write an escape sequence (`TerminalSession` pushes the
keyboard flags when the terminal answers its query). `SerializedConnection` wraps a connection so each write
holds a lock while it runs; a sequence then lands before a frame or after it, never inside it. Tested with a
connection that appends byte by byte: two threads writing 2,000 bytes each leave two whole runs through the
wrapper and interleave without it (the control, run beside it).
