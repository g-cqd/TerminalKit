# TerminalKit — Project White Paper

The rules this package runs on. **Paste this at the start of every iteration.** The same law governs
`ask`, which is where it was first written; this is the copy that travels with the terminal code,
because Atelier, KittyCode and `ask` all build on this package.

## Runtime principles

These are what "fast" is allowed to mean here. They bind every target in the ecosystem, and each one
excludes something that would otherwise look like an optimisation.

**A lightweight runtime.** A binary links only what it uses. No umbrella target that re-exports
everything, no speculative generality, no framework pulled in for one function. Startup cost is paid
once per process, so every linked module is paid for at every launch.

**Fewest allocations.** Allocation is not free and it is not only slow — it fragments, and a fragmented
allocator costs more in cache misses than the work that needed it. The hot path allocates zero times,
and a buffer is reused rather than re-made. Where a budget can be stated it is **measured and enforced
by a test**, because an allocation ceiling nobody checks is a wish.

**Close to zero copy.** Work in `ContiguousArray` and `UnsafeMutableRawBufferPointer` from the boundary
inward. No `Array`/`ContiguousArray` bridging, no `String` round-trip per keystroke, no copying a
buffer to append to it. Copy once, at the edge where data enters or leaves the process. Copy-on-write
is what a runtime reaches for when it cannot avoid a copy; here the aim is to have nothing to copy.

**Safest, and still near zero-copy.** These are requirements together, never a trade against each
other. No `-Ounchecked`, no disabled bounds or overflow checks, no `unsafe` that is not immediately
justified in a comment. The way to be both fast and safe is to **do less work** — diff a frame instead
of repainting it, reuse a buffer instead of allocating one, decode a byte once instead of re-scanning
it — not to remove the checks that catch the bugs.

**Every claim is measured.** A performance claim without before-and-after numbers, same harness, same
configuration, with units, is not a claim this project will act on.

**Generic tools belong in Aemi.** A tool that is not specific to one application does not live inside
that application. It is promoted to Aemi, the kernel package, and the specialised packages build on it
from there. This is not only about `ask`, TerminalKit, Atelier or KittyCode — it is a standing rule
for anything encountered anywhere in the ecosystem: if Aemi's scope would serve it better than a
single consumer's, it goes to Aemi. The test is whether a second consumer is plausible, not whether
one exists today.

The consequence is accepted rather than avoided: Aemi grows, and promoting something into it is a real
change to a package other projects depend on, so it is measured, reviewed and pinned by dependents
like any other.

---

## 0. The Evidence Rule

> **Every claim is challenged and backed by an actual probe before it is adopted or acted on.
> There is no place for an assumption.**

**What is a claim:** anything stated as fact about a toolchain, a protocol, a performance number, a
library's behaviour, or a platform's guarantee. If acting on it would be expensive to undo, it is one.

**What is a probe:** running the thing and observing the result — a build, a test run, a benchmark, a
command's output, a read of authoritative documentation. A recollection of how a tool "usually"
behaves is not a probe.

**The protocol:** name the claim as a sentence that could be true or false → design a probe that would
make it false if it is false → run it and record the command verbatim → record the verdict in the diary → act only then. An unprobed claim is written down as an open question, never as a fact.

**Not a probe:** confidence or experience; a blog post or a second model; documentation read out of
context; a passing build that does not distinguish between the hypotheses; inference from a different
configuration than the one shipping.

**The bisect lesson.** A flag was blamed for a failure that had nothing to do with it, because it was
cleared by removing it from a build that still failed for the real reason. A probe that cannot fail
proves nothing.

## 1. Red TDD

- **Red first**, confirmed failing **for the right reason**, before the implementation exists. A test
  that has never failed has proven nothing.
- One behaviour per test, named in backticks as a sentence: ``@Test func `the soft tier spares the scrollback`()``.
- Green by the minimum *general* code. Refactor with tests green, one named move at a time.
- **Red and green land in the same commit** — the red is observed locally and recorded, never left
  broken on the main line, so `git bisect` keeps working.
- Never: assert on nothing, sleep or time out inside a test, share mutable state between tests, test a
  private method to test itself.
- Coverage is measured by behaviour, never by percentage.

## 2. Performance doctrine

- **No optimisation without a measurement showing the bottleneck and a second measurement proving the
  fix** — before/after, same harness, same inputs, same build, with units.
- **Release only.** A debug build measures a program nobody ships.
- **Percentiles, not averages.** Median and spread, never the best run.
- Budgets are numbers with units. An unmeasured budget is not a budget.
- Order of attack: don't do the work → do less work → do it elsewhere → do it in parallel →
  micro-optimise last.
- **Never trade correctness or safety for speed.** No `-Ounchecked`, ever.

## 3. Verification of terminal behaviour

Byte-exact tests are necessary and **not sufficient**. Proving the bytes are not the same claim as
proving a terminal obeys them, so both are required:

- **Byte-exact tests** — the encoder emits exactly the sequence intended.
- **Oracle tests** — an independent model of the terminal's semantics, written from the
  specification, driven with the real emitted bytes. Two implementations that agree is evidence; one
  agreeing with itself is not.
- **Real-emulator tests** — owed, and recorded as owed until they run. A model is not an emulator.

## 4. Swift package strictness

Verified against Swift Evolution; see the table in `ask`'s white paper for the SE references. Do not
add a flag that is not justified by a probe, and do not remove one without a probe showing the package
is better without it.

`.swiftLanguageMode(.v6)` (which already implies `RegionBasedIsolation`,
`DisableOutwardActorInference`, `InferSendableFromCaptures`, `DeprecateApplicationMain`),
`StrictMemorySafety`, `ExistentialAny`, `InferIsolatedConformances`, `InternalImportsByDefault`,
`MemberImportVisibility`, and warnings as errors.

Build optimized white-box tests with explicit testability; build shipping and benchmark binaries
separately without it. Testing mode is a build choice, not a reason to widen the public API.

**Banned:** `-Ounchecked`. It strips the bounds and overflow checks `StrictMemorySafety` relies on.

## 4b. Style and size

- **Style is Aemi's canonical configuration**, copied by `Aemi/scripts/sync-config.sh`, not re-derived
  per package. ADR-0003.
- **swift-format owns style; SwiftLint owns size and complexity.** The synced `.swiftlint.yml` uses
  `only_rules`, so the two tools structurally cannot argue.
- `Scripts/quality.sh` is the only entry point; `--check` is what CI runs. Format drift is a red build.
- Build and test in **release**, always.

## 5. Documentation law

- `docs/adr/NNNN-title.md` — **one decision per file**. A decision changed by evidence is a **new ADR
  that supersedes** the old one; records are not edited into an unrecognisable shape.
- `docs/roadmap/NNNN-title.md` — **one entry per file**, the unit of work. Every entry declares a
  `status:` field and one top-level title.
- `docs/diary/YYYY-MM-DD-NN.md` — the working log, and **where probe history lives**. No file over
  256 lines; roll over at the ceiling.
- `docs/WHITE-PAPER.md` — this file. It is **principles, not a log**: it changes when a principle
  changes, and never when a probe runs. Probe history belongs in the diary.
- The law is **enforced by tests in this repository**, not merely requested.

## 6. Commit discipline

Atomic and buildable. The message states **why**. Never mix a refactor and a behaviour change. Slice
by behaviour. Report residual risk and follow-ups explicitly.

## 7. Bans

Unmeasured optimisation. Unprobed claims. Best-run reporting. Debug-build benchmarking. Sleeps or
timeouts in tests. Big-bang rewrites. Drive-by churn. Adding a dependency for convenience — **a
dependency is an architectural decision**.

---
