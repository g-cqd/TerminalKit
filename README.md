# TerminalKit

A shared Swift terminal stack extracted from Atelier for KittyCode and `ask`.
Repository: <https://github.com/g-cqd/TerminalKit>.

Requires Swift 6.4 and macOS 26. Kernel utilities come from Aemi at the revision pinned in
`Package.swift` and `Package.resolved`.

## Start here

- [White paper](docs/WHITE-PAPER.md): stable principles, not experiment history.
- [ADRs](docs/adr): decisions and supersession links.
- [Roadmap](docs/roadmap): one file per work entry, including incomplete work.
- [Diary](docs/diary): probe history, at most 256 lines per file.

## Products

| Product | Responsibility |
|---|---|
| `TerminalKitCore` | Reset sequence values |
| `TerminalKitIO` | Terminal connections, raw mode and geometry |
| `TerminalKitStyle` | Style value types |
| `TerminalKitCodecs` | Escape encoders and keyboard/mouse decoders |
| `TerminalKitInput` | Input routing, streams, signals, and terminal sessions (modes entered and left as a unit) |
| `TerminalKitText` | Rope, text operations and display metrics |
| `TerminalKitRender` | Screen buffers, frame differences and output |
| `TerminalKitTestSupport` | Terminal model and measurement helpers |
| `TerminalKit` | Core re-export; excludes test support |

## Verify

```sh
Scripts/quality.sh --check
# Or build/run optimized tests directly:
swift test -c release --enable-testable-imports
# Re-run that build without recompilation:
swift test -c release --skip-build
```

The gate runs format checks, SwiftLint metrics and optimized tests. Select testability explicitly
for internal tests (SE-0455); `swift build --build-tests -c release` is not equivalent.
See [ADR-0012](docs/adr/0012-explicit-release-testability.md) for the controlled reproduction.

Build shipping binaries and run performance measurements separately without testability.

Time benchmarks live in their own package ([ADR-0017](docs/adr/0017-time-benchmarks-compare-two-runs-on-one-machine.md)):

```sh
Scripts/benchmarks.sh                 # run every suite
Scripts/benchmarks.sh compare main    # this tree against main, same machine; fails on a regression
Scripts/benchmarks.sh record          # rewrite Benchmarks/REFERENCE.md
```

`Scripts/verify-scroll-region.sh` runs the real pipeline with a scroll region inside kitty, wezterm and
Terminal.app and reads their screens back ([ADR-0022](docs/adr/0022-scroll-regions-are-detected-not-declared-per-frame.md)).

## Progress

All six extracted modules compile, and the owning IO/codec/input/renderer/text suites run here.
The current release run reports **397 tests across seven targets**; opt-in performance benchmarks
are skipped by default. This is correctness validation, not a new performance measurement.

Atelier consumes these modules directly, with no copies left
([entry 0003](docs/roadmap/0003-atelier-consumes-terminalkit.md)). The keyboard decoder, the input
router and the frame flush allocate nothing on their hot paths, and every release suite enforces it
([ADR-0016](docs/adr/0016-hot-path-ceilings-in-every-suite.md)).

## Emulator verification

Byte tests, the terminal model and emulator probes address different claims. Scripts under
`Scripts/verify-*` exercise real emulators; their scope and limitations are recorded in
[ADR-0004](docs/adr/0004-screen-and-scrollback-preservation-measured.md).
Do not infer universal terminal behavior from a model or one emulator's result.
