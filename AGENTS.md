# Working in `TerminalKit`

Shared Swift 6 terminal I/O, codec, text, rendering, and TUI framework (`g-cqd/TerminalKit`).

## Engineering principles

- **Verify claims with executable checks.** Measure render/diff paths and verify terminal state restoration with real PTY tests.
- **Strictness.** Swift 6 language mode, strict memory safety, warnings as errors.
- **Terminal invariants.** Every mode entered in a terminal session must be left symmetrically on normal exit, cancellation, or signal termination; escape decoders must bound buffer growth on hostile sequences.
- **Factual documentation.** Keep `README.md`, `docs/adr/`, and `Package.swift` aligned with the current codebase.

## Commands

```sh
swift test
swift format lint --strict --recursive Sources Tests Package.swift
```
