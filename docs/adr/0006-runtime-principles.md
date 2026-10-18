---
status: accepted
date: 2026-10-18
---

# 0006 — Runtime principles: lightweight, fewest allocations, near zero-copy, safe

## Context

The project has repeatedly described itself as fast without saying what *fast* is allowed to mean.
That is not a neutral gap. Left undefined, "optimise this" tends to produce the fastest-looking
change rather than the right one, and the fastest-looking change is usually `-Ounchecked`.

These are principles, so they are recorded as principles — in the white papers, where they bind every
target in the ecosystem rather than one package.

## The principles

**A lightweight runtime.** A binary links only what it uses. No umbrella re-export, no speculative
generality, no framework for a single function. Startup is paid on every launch, so every linked
module is charged to every cold start.

**Fewest allocations.** Allocation is not merely slow; it fragments, and a fragmented allocator costs
more in cache misses than the work that wanted it. The hot path allocates zero times and reuses its
buffers. A ceiling that is not measured and checked is a wish, so ceilings here are **tests**.

**Close to zero copy.** Work in `ContiguousArray` and `UnsafeMutableRawBufferPointer` from the boundary
inward. No `Array`/`ContiguousArray` bridging, no `String` round-trip per keystroke, no copy-to-append.
Copy once, where data enters or leaves. Copy-on-write is the fallback when a copy cannot be avoided;
the aim is to have nothing to copy.

**Safest, and near zero-copy.** These are requirements together. No `-Ounchecked`, no disabled bounds
or overflow checks, no `unsafe` without a justification at the point of use. Being fast *and* safe is
achieved by doing less work — diffing a frame instead of repainting it, reusing a buffer instead of
allocating one — not by removing the checks that catch the bugs.

## Consequences

- **The allocation ceiling becomes a test.** Aemi's test kit exposes `expectAllocations(noMoreThan:)`,
  so a hot path's allocation count can be asserted rather than described. That function is the reason
  this decision is enforceable at all.
- **A ceiling is set from a measurement, never from a guess.** The white paper's evidence rule applies
  to performance numbers exactly as it applies to protocol claims.
- **`TerminalKitTestSupport` stays out of the shipping umbrella.** An oracle is a test double; a
  shipping binary that links one has paid for something it never consults.
- Existing code is not exempt. The moved terminal modules arrived with whatever allocation behaviour
  they had, and the ceilings will find the places that do not meet the principle.

## What this forbids

Reaching for `-Ounchecked`, for a disabled check, or for a "zero-copy" rewrite that widens the
unsafe surface, in order to make a number look better. If a budget cannot be met by doing less work,
the budget is wrong and gets revisited — not the safety.