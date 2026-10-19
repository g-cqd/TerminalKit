---
status: not-started
blocked-by: ["0006"]
date: 2026-10-19
---

# 0014 — Decide the render pipeline's isolation

`RenderPipeline` is `@MainActor`. That forced ask's screen loop onto the main actor, and stopped ordo-one
benchmarks from measuring the pipeline directly (their closures cannot be actor-isolated), so ask added a
separate probe executable. Evaluate a nonisolated, value-type core (buffers, diff, encode) with a thin
isolated driver. Also decide whether frame signposts are always on (they allocate nothing, ADR-0016) or opt-in.
Measure both choices with 0006.

**Update (2026-10-19, ADR-0017):** package-benchmark runs `@MainActor` async closures, so the pipeline is
benchmarked directly. The benchmarks are no longer a reason to change the isolation; the evaluation stays
open on its other grounds (ask's screen loop on the main actor).
