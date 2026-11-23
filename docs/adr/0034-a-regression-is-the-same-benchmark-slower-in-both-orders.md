---
status: accepted
date: 2026-11-23
---

# 0034 — A regression is the same benchmark slower in both orders, both trees built clean side by side

## Context

ADR-0017 compares two runs on one machine. CI already ran a second comparison in the other order when the first exceeded the
thresholds, and failed when both did. On 2026-11-22 a Dependabot pull request that changed only the benchmark harness, no source, failed
that way: 5 benchmarks base first, 17 head first, none in common. Locally the same identical code failed again, and three input
decoders came out 6 to 13 % slower in both orders: this tree was built in place, incrementally, under its checkout's path, the base clean
in a temporary worktree.

## Decision

1. `Scripts/benchmarks.sh gate <rev>` compares in both orders and fails only on a benchmark that regressed in both. CI runs it.
2. `compare` measures this tree from a copy beside the base's worktree (`$scratch/head`, `$scratch/base`), built clean as the base is.

## Consequences

Measured on this machine (diary 2026-11-23-01): identical code passes (3 base first, 12 head first, none in common); a slowdown put in
`UnicodeWidth.displayWidth(of:)` fails, all three `width/*` benchmarks and the CJK wrapping among the 13 in both orders. Both trees now
build clean, so a comparison takes longer; the cached benchmark build no longer serves this tree's side.
