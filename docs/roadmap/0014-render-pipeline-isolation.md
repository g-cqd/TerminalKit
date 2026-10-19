---
status: done
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

## Done (2026-10-19)

ADR-0026. Stress-tested four ownerships under load; the pipeline belongs to no actor, and `RenderLoop` draws
the newest state on its own thread. A key is handled in 0.01 ms whatever a frame costs, where the main actor
took up to 2 s behind a 2 ms frame at 5,000 lines a second. Signposts are opt-in: a one-cell flush is 0.35 µs
without them, from 0.79.
