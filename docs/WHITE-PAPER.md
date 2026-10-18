# TerminalKit — Project White Paper

The rules this package runs on. **Paste this at the start of every iteration.** The same law governs
`ask`, which is where it was first written; this is the copy that travels with the terminal code,
because Atelier, KittyCode and `ask` all build on this package.

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
make it false if it is false → run it and record the command verbatim → record the verdict → act only
then. An unprobed claim is written down as an open question, never as a fact.

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
`MemberImportVisibility`, warnings as errors, and the two `-warn-long-*` limits.

**Banned:** `-Ounchecked`. It strips the bounds and overflow checks `StrictMemorySafety` relies on.

## 5. Documentation law

- `docs/adr/NNNN-title.md` — **one decision per file**. A decision changed by evidence is a **new ADR
  that supersedes** the old one; records are not edited into an unrecognisable shape.
- `docs/roadmap/NNNN-title.md` — **one entry per file**, the unit of work. Every entry declares a
  `status:` field and one top-level title.
- `docs/diary/YYYY-MM-DD-NN.md` — the working log and the probe ledger. **No file over 256 lines**;
  roll over at the ceiling.
- The law is **enforced by tests in this repository**, not merely requested.

## 6. Commit discipline

Atomic and buildable. The message states **why**. Never mix a refactor and a behaviour change. Slice
by behaviour. Report residual risk and follow-ups explicitly.

## 7. Bans

Unmeasured optimisation. Unprobed claims. Best-run reporting. Debug-build benchmarking. Sleeps or
timeouts in tests. Big-bang rewrites. Drive-by churn. Adding a dependency for convenience — **a
dependency is an architectural decision**.

---

## Probe ledger

Every entry is a claim, the probe that tested it, and the verdict. It only grows with probes that ran.

| # | Claim | Probe | Verdict |
|---|---|---|---|
| 1 | The strict upcoming-feature flags exist in Swift 6.4 | `apple-docs` search over `swift-evolution` | **CONFIRMED.** SE-0458 (6.2), SE-0409 (6.0), SE-0444 (6.1), SE-0470 (6.2), SE-0335. |
| 2 | The reset escape sequences are correct | Byte-exact comparison against literals | **REFUTED.** `ESC [ ? 1006 l` and `ESC [ ? 2004 l` were each a byte short — mouse reporting and bracketed paste would have stayed on after a crash. |
| 3 | The terminal model matches terminal semantics | Eight oracle tests over the real emitted bytes | **REFUTED.** Mode 25 is inverted relative to other private modes (`h` shows the cursor); the model had it backwards. The oracle found a bug in the oracle. |
| 4 | The terminal stack is three modules, 3,530 lines | `grep` of imports, extended through the closure | **REFUTED.** Six modules, 6,263 lines, including `AtelierText` from another package. |
| 5 | A real kitty instance can verify the tiers from here | `kitty @ ls` | **REFUTED.** `open /dev/tty: device not configured` — kitty 0.49.2 is installed, but this session has no controlling TTY, so the emulator check cannot run here. |
| 6 | A PTY is available for a harness | `util.h` in the macOS SDK | **CONFIRMED.** `openpty` is declared at `util.h:99`. Not yet used. |
| 7 | The reset tiers can be verified against real terminals from here | `kitty --config NONE -o allow_remote_control=yes --listen-on=tcp:…` | **CONFIRMED, with care.** A dedicated kitty instance answers remote control. The first harness was wrong in two ways — `--extent=history` is not a valid extent, and double-quoted `\033` became a real ESC that `send-text` swallowed, so every tier ran as a no-op and reported PASS. |
| 8 | kitty's remote control can be reached without touching the user's config | `kitty --help` for `--listen-on` and `-o` | **CONFIRMED.** A separate instance on a private port. No user config modified. |
| 9 | A live terminal can be asked what modes it has set | DECRQM (`CSI ? Ps $ p`) round trip on `/dev/tty` | **CONFIRMED.** Replied with `n` for every query on kitty, ghostty, wezterm; **Terminal.app answers nothing**, so it is INCONCLUSIVE there. |
| 10 | DECSTR resets DEC private modes | Same DECRQM probe, tier 2, four emulators | **REFUTED — by the emulators, against us.** DECSTR left `?1049`, the mouse modes and `?2004` set on kitty, ghostty and wezterm. The oracle and the docs were wrong. ADR-0002. |
| 11 | The selective tier clears the private modes it names | Same probe, tier 1 | **CONFIRMED.** PASS on all three emulators that report mode state. This is the tier that does the work. |
| 12 | Mode 25 behaves like the other private modes | DECRQM on `?25` | **REFUTED, twice.** `1` means *visible*. It made the oracle report a healthy terminal as broken, then made the first verifier do the same. Inverted handling is now explicit in both. |

**Open questions — not probed, therefore not acted on:**

- **Scrollback preservation is still unmeasured.** DECRQM reports modes, not history. Tiers 1 and 2
  emit no `ESC c`, which is why they *cannot* clear the screen, but "spared the scrollback" is
  structural reasoning plus an oracle, not a measurement.
- **Terminal.app is unverified.** It answers no DECRQM. It needs a technique based on observable
  screen state instead of mode queries.
- Whether `openpty` is reachable from Swift without an Objective-C shim.