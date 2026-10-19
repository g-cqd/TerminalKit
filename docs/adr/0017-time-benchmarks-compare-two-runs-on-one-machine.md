---
status: accepted
date: 2026-10-19
---

# 0017 — Time benchmarks compare two runs on one machine, and gate on the lower quartile

## Context

ADR-0016 holds the router and the flush to zero allocations. Nothing held them to a time (roadmap 0006).
package-benchmark offers two gates: static thresholds recorded once and checked later, and a comparison of
two baselines taken on the same machine.

## Measured

Three full runs of identical code on the development machine (M2 Pro, 10 cores), under the load of other
agents' builds (load average 10), compared pairwise. Worst change between any two runs, per suite:

| Percentile | Worst change | Where |
|---|---|---|
| p25 | 9 % | `flush/80x24 one row` |
| p50 | 92 % | `flush/80x24 one cell`: 2.0 µs in one run, 4.0 µs in the next |
| p90 | 142 % | `flush/300x80 one row` |

The median jumps when a whole run lands on slower cores, and the tail moves with the load. The lower
quartile is the only percentile that stayed inside 10 %.

package-benchmark's static thresholds record and check **p90 only**
(`BenchmarkTool+Thresholds.swift`), the percentile that moved 142 %.

## Decision

- **The gate is a comparison**: `Scripts/benchmarks.sh compare <rev>` times `<rev>`'s library and this
  tree's library with this tree's benchmark code, in a temporary worktree, on the same machine, then runs
  `baseline check`. CI runs it on every push to `main` and every pull request, against the base.
- **Thresholds** (`Benchmarks/Sources/BenchmarkSupport`): wall clock may regress 15 % at p25;
  allocations may not grow at p25, p50 or p90. The median and the tail are printed, not enforced.
- **Reference numbers** are checked in as `Benchmarks/REFERENCE.md`, written by
  `Scripts/benchmarks.sh record` with the commit, the time and the load average. A roadmap entry quotes
  its before and after from there. The 2 MB baseline JSON is not checked in.
- **What is measured**:
  - per event, for decoding: 1,000 events per sample through the public `feedAll`, scaled by 1,000;
  - per grapheme, for `UnicodeWidth`: 1,000 per sample, scaled by 1,000;
  - per frame or per operation for the rest: each sample builds and warms its buffers, then times one
    operation.
- **The boundary is the terminal write.** Frames flush into a connection that keeps only the byte count,
  not into `MockTerminalConnection`, whose output array grows for the whole run.

## Consequences

- A regression that moves the whole distribution fails. One that moves only the tail does not; on a
  shared machine the tail cannot be told apart from load.
- CI compares on a shared runner whose noise has not been measured. If it proves noisier than this
  machine, the threshold is revisited from those numbers, not loosened by guess.
- `@MainActor` async closures run in package-benchmark, so the render pipeline is measured directly. That
  refutes the premise in roadmap 0014 that its closures cannot be actor-isolated.
- `plugin` exits 1 for a regression and for an improvement alike; `compare` tells them apart by the
  plugin's message.
