---
status: done
date: 2026-10-18
---

# 0005 — Resolve blocker 2 with explicit release testability

Outcome: a test target can `@testable import TerminalKitCodecs`, link the library and assert
the decoder's result in optimized tests, without changing library code or exposing internals.

- Root cause and command-by-command evidence: ADR-0012.
- Red: `swift build --build-tests -c release` fails on the import.
- Green: `swift test -c release --enable-testable-imports` passes.
- Negative control: `--disable-testable-imports` restores the same failure.
- Original timing flags also pass with testability enabled, refuting the earlier flag diagnosis.
- Permanent regression: `Tests/TerminalKitCodecsTests/KeyboardDecoderTests.swift`.
- Quality gate explicitly enables testability; shipping builds remain separate.

Atelier remains unchanged. Porting its existing terminal suites is the next step in entry 0003.
