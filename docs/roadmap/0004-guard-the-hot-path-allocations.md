---
status: done
blocked-by:
date: 2026-10-18
---

# 0004 — Guard the hot path's allocations

Measure and enforce a justified allocation budget on real decoder workloads.
ADR-0003 records the finding and the measurement conditions.

## Done

- The counter was validated in the same configuration before any budget was set: 1,000 string
  allocations count 1,011, and the instrument detects a deliberate allocation as a control.
- The decoder's hot path was measured: **1,335 allocations per 1,000 keystrokes**, from
  `removeAll()` releasing the buffer's storage. Fixed with `keepingCapacity: true`; now **0**.
- The ceiling is enforced: `count == 0` for 1,000 keystrokes, with a control that must detect an
  allocation. Reverting the fix reports exactly 1,000 and fails; restoring it passes.
- At the time, the measurement ran in an empty process: opt-in through `TERMINALKIT_ALLOC=1`, `.serialized`
  within its suite, and a CI job of its own. In the full suite the same measurement read as 101
  because other suites' threads contribute; a ceiling judged against that would be a ceiling on the
  test runner.
- Missing instrumentation fails the test rather than passing it.
- The reusable helper was promoted to Aemi as `minimumAllocations(repeats:body:)`.

## Router and frame flush (ADR-0016)

- Router: every key kind measured 0 per read after the fixes (Escape, arrows, Kitty keys, SGR mouse,
  UTF-8 were 1–3); a 1 KiB paste allocates once, for its `String` (was 5).
- Frame flush: 0 whether idle, changing every row, or scrolled (was 4, 11, 11).
- Aemi now counts only the measuring thread, so every ceiling runs in the default release suite;
  the `TERMINALKIT_ALLOC` gate and the separate CI job are gone.

## Still owed

- Throughput and latency continue to be measured on a separate shipping release build, never on the
  testable build used for white-box correctness.
