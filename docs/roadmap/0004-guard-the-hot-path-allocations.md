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
- The measurement runs in an empty process: opt-in through `TERMINALKIT_ALLOC=1`, `.serialized`
  within its suite, and a CI job of its own. In the full suite the same measurement read as 101
  because other suites' threads contribute; a ceiling judged against that would be a ceiling on the
  test runner.
- Missing instrumentation fails the test rather than passing it.
- The reusable helper was promoted to Aemi as `minimumAllocations(repeats:body:)`.

## Still owed

- Ceilings for the other hot paths: the renderer's frame flush, and the input router. The same
  isolation rule applies, and the same measurement conditions.
- Throughput and latency continue to be measured on a separate shipping release build, never on the
  testable build used for white-box correctness.
