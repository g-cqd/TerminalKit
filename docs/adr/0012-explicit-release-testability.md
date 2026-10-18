---
status: accepted
supersedes: [ADR-0010, ADR-0011]
date: 2026-10-18
---

# 0012 — Resolve blocker 2 by selecting testability explicitly

## Root cause

The failing reproduction used `swift build --build-tests -c release`, which did not enable
library testability; `swift test -c release --enable-testable-imports` does. The investigation
mistook commands with different settings for equivalent builds.

No metadata emission flag, resilience change, or public API widening is necessary.

## Evidence

A permanent `TerminalKitCodecsTests` target declares `TerminalKitCodecs` as a dependency and
uses `@testable import TerminalKitCodecs`. Its test decodes ASCII and checks the complete event.
On Apple Swift 6.4, with the default `swiftbuild` engine:

| Command / control | Exit | Result |
|---|---|---|
| `swift test -c release --filter KeyboardDecoderTests` | 0 | Test passes |
| `swift build --build-tests -c release` | 1 | Compatible-module error at `@testable import` |
| `swift test -c release --enable-testable-imports --filter KeyboardDecoderTests -v` | 0 | Test passes; Codecs compile command includes `-O -whole-module-optimization -enable-testing` |
| Same test with both original timing `unsafeFlags` temporarily restored | 0 | Test passes |
| `swift test -c release --disable-testable-imports --filter KeyboardDecoderTests` | 1 | Same compatible-module error |
| `swift test -c release --skip-build --filter KeyboardDecoderTests` after enabled build | 0 | Test runs without rebuilding |

The timing-flag experiment changes only the two manifest settings, then restores them.
It refutes the earlier claim that `unsafeFlags` inherently disables testability.
This does not establish that arbitrary unsafe flags are safe or suitable for dependencies.

Apple-docs MCP supplied **SE-0455, SwiftPM @testable build setting**:
`swift-evolution/0455-swiftpm-testable-build-setting`. It describes debug-enabled,
release-disabled defaults and says explicitly passing the CLI override forces testing on/off.
The installed `swift test --help` also exposes that override.

Xcode MCP could not list workspaces: this agent lacks Xcode approval. No Xcode IDE validation
is claimed; the compiler commands and SwiftPM test exits above are the validation.

## Decision

- The quality gate runs `swift test -c release --enable-testable-imports`.
- Keep the codec test target in CI so the previously untested library is actually linked and
  checked. A failed build is a failed gate, not an empty test run.
- Keep declarations at their current access levels. Moving tests must not widen the library API.
- Shipping binaries and performance measurements use ordinary optimized release builds without
  testability; optimized test builds are not claimed to be byte-identical shipping binaries.
- Leave the timing flags absent for now. They are not banned on a false testability premise;
  reintroducing timing budgets would need its own compile-time measurement and dependency review.

## Corrections to prior records

ADR-0011 already retracts the missing-metadata diagnosis correctly. Its remaining unexplained
inconsistency is resolved by the command comparison above. ADR-0010's blanket claims about
`unsafeFlags` and package boundaries were not established and must not guide implementation.
`ask` ADR-0002's statement that release testing makes `@testable` impossible is also incorrect;
public-API testing remains a preference, not a toolchain limitation.

## Consequences

Blocker 2 is resolved. The next independently verifiable step is to import Atelier's existing
terminal suites, build them with this command, and only then switch Atelier's implementations
to TerminalKit. No Atelier source removal is part of this fix.
