---
status: done
blocked-by: 
date: 2026-10-19
---

# 0006 — A benchmark suite for time, not only allocations

ADR-0016 holds the input router and the frame flush to zero allocations in every suite. Nothing holds them
to a *time*, so a change that keeps allocations at zero but doubles a frame's cost passes.

## What lands

- A separate `Benchmarks/` package on ordo-one package-benchmark, depending on TerminalKit by path, as ask's
  does. The shipping graph never resolves the framework, and it measures the working tree.
- **Suites, each at 80×24, 120×40 and 300×80:**
  - decode per event: text, escape, Kitty key, mouse, paste;
  - `ScreenBuffer.write` of new text and of identical text;
  - `flush` for one changed cell, one changed row, and the full screen;
  - `forceRedraw`;
  - `UnicodeWidth` over ASCII, CJK and emoji.
- Baselines checked in, and a regression threshold per suite in CI.

## Why first

Every other entry below changes a hot path. Each needs a before and an after on the same harness.

## Done (2026-10-19)

- `Benchmarks/` holds every suite above, at all three sizes; ADR-0017 records the design.
- `Scripts/benchmarks.sh compare <rev>` gates a change against its base on one machine; CI runs it on
  `main` and on pull requests. Thresholds: 15 % at p25 for time, no growth for allocations.
- `Benchmarks/REFERENCE.md` holds the reference numbers, from `Scripts/benchmarks.sh record`.
- Not done as written: the checked-in thresholds are a readable table, not package-benchmark's static
  thresholds, which gate at p90 only (ADR-0017).
