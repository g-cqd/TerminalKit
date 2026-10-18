---
status: accepted
date: 2026-10-18
---

# 0008 — The keyboard decoder allocated once per keystroke, and a ceiling needs an empty process

## Context

The runtime principle says fewest allocations, with ceilings that are measured rather than
described. No quantitative hot-path ceiling existed. Entry 0004 required validating Aemi's
allocation counter before setting a budget, in an isolated process.

## The finding

`KeyboardDecoder.feed` — one call per keystroke byte, on the thread that must answer before the
user sees anything — allocated **once per keystroke**.

The cause was in `reset()`: `buffer.removeAll()` releases the array's storage, so the next `append`
reallocates. `alternateKeys` and `textCodepoints` had the same shape. `removeAll(keepingCapacity: true)`
holds the capacity; the buffers are tiny and the decoder is long-lived, so keeping them costs nothing.

Measured over 1,000 keystrokes, with the counter exact on the thread that opens the window:

| | allocations per 1,000 keystrokes |
|---|---|
| before | **1,335** (1,000 from the buffer, the rest from the result path) |
| after | **0** |

The counter itself was validated in the same configuration: 1,000 string allocations count 1,011 and
1,000 array appends count 12, because `Array` growth is amortised. An earlier probe of mine expected
1,000 from 1,000 appends and failed — the probe's expectation was wrong, not the counter.

## The ceiling, and why it needs an empty process

The guard is `count == 0` for 1,000 keystrokes, with a control that must *detect* an allocation in
the same configuration.

It cannot run in the default suite. Measured: in isolation the decoder's 0 allocations read as 0, and
inside the full suite the same measurement read as **101** — other suites' allocations, from threads
that start inside the measurement window. A ceiling judged against that number would be a ceiling on
the test runner, not on the decoder. So:

- The tests are **opt-in** through `TERMINALKIT_ALLOC=1`, and skipped otherwise.
- The suite is **`.serialized`**, so its own two tests do not contaminate each other. Without that,
  the control's 100 string allocations landed in the decoder's window and the gate failed at 101.
- CI runs them in a **job of its own**, an empty process but that one.

Missing instrumentation fails the test rather than passing it: `try #require` throws when the counter
is unavailable, so an unmeasurable platform is a red build, never a green one.

## The mutation check

Reverting the fix makes the gate report **exactly 1,000 allocations for 1,000 keystrokes** and fail.
Restoring it reports 0 and passes. The guard bites in both directions.

## Consequences

- The hot path's allocation ceiling is now enforced, and the decoder no longer allocates per keystroke.
- The reusable measurement helper lives in **Aemi** (`minimumAllocations(repeats:body:)`), not in a
  terminal-specific copy: it takes the minimum across repeats because contamination can only push a
  count up, and a minimum is the conservative, stable sample to judge a ceiling against.
- A regression that reintroduces a per-keystroke allocation fails CI in its own job.
- The same isolation rule applies to any future allocation ceiling: **measure in an empty process.**
