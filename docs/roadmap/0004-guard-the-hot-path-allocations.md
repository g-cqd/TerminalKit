---
status: not-started
blocked-by:
date: 2026-10-18
---

# 0004 — Guard the hot path's allocations

Measure and enforce a justified allocation budget on real decoder/rendering workloads.
No quantitative hot-path ceiling is currently enforced.

## Build blocker resolved

ADR-0012 resolves codec testability. The new owning suites compile, link and run with
`swift test -c release --enable-testable-imports`; no metadata or resilience changes are needed.
The earlier explanation about missing generic descriptors is false.

The renderer test target also imports AemiTestKit successfully at the existing `d0f8108` pin.
Do not assume exposing additional C products is required to use it.

## Measurement work still required

- `ProcessFootprint` reports process-wide retained memory, not allocations per operation.
  Its tests verify availability and detectable growth; they do not prove zero allocation or
  proportional growth under parallel execution. Earlier claims of both-direction precision
  were removed after flaky/failing experiments.
- Inspect and validate Aemi's allocation counter in an isolated process before setting a budget.
  The earlier thread-scope diagnosis is not a substitute for a controlled, synchronized probe.
- Preserve results so the optimizer cannot eliminate the measured work. Confirm the instrument
  detects an intentionally allocating control under the same configuration.
- Keep throughput/latency measurements on a separate shipping release build, not the testable
  build used for white-box correctness tests.
- Promote reusable measurement helpers to Aemi rather than growing a terminal-specific copy.

## Done when

A reproducible isolated workload has a measured allocation baseline and ceiling, an intentionally
allocating mutation exceeds it, and the normal workload stays inside it. Missing instrumentation
must report inconclusive/failure rather than a false pass.
