---
status: accepted
date: 2026-10-18
---

# 0003 — Style is Aemi's canonical config, synced rather than reinvented

## Context

`ask` and TerminalKit were formatted with whatever `swift-format` did by default — two-space
indentation, the tool's own line length. Aemi meanwhile had a developed canonical configuration with a
documented rationale. Two packages in one ecosystem, formatting differently, is how a shared codebase
starts looking like two codebases.

## The probes

**Probe 1 — does a canonical configuration already exist?** Read Aemi's `.swift-format`,
`.swiftlint.yml` and `.swift-version`.

**CONFIRMED, and better than inventing one.** Aemi's `.swift-format` sets four-space indentation, a
120-column limit, `fileScopedDeclarationPrivacy: private`, ordered and grouped imports, and a rule set
that includes `AvoidRetroactiveConformances`, `NeverUseImplicitlyUnwrappedOptionals`,
`FullyIndirectEnum`, `IdentifiersMustBeASCII` and `DoNotUseSemicolons`. `.swiftlint.yml` is
deliberately **metrics-only**: SwiftLint runs with `only_rules`, so it contributes file length, type
and function body length, cyclomatic complexity, arity and nesting — the things formatting cannot
express — and structurally **cannot** fight the formatter over a style question.

**Probe 2 — is there a supported way to share it?** Aemi ships `scripts/sync-config.sh`, and a
`swift-quality.yml` workflow that fails on drift.

**CONFIRMED.** The intended model is a single source of truth propagated to consumers, not a style
re-derived per package.

**Probe 3 — does the gate actually fail?** Injected two-space indentation and an over-long line into
`TerminalReset.swift` and ran the gate.

**CONFIRMED.** `error: [Indentation] indent by 2 spaces`, `[FAIL] formatting drift`, exit 1. Restored,
the gate reports `[OK] clean`. A gate that cannot fail proves nothing, so this was checked rather than
assumed.

## Decision

- `.swift-format`, `.swiftlint.yml` and `.swift-version` are **copied from Aemi**, by its own
  `sync-config.sh`, into every package in the ecosystem.
- One entry point, `Scripts/quality.sh`, with `--check` for verification. CI runs `--check`, so a
  formatting drift is a red build rather than something a reviewer has to notice.
- Release configuration for build and test, in the gate and in CI, because a debug build measures a
  program nobody ships.

## Consequences

- Adopting the config reformatted existing sources — a large but mechanical diff. It is separated from
  any behaviour change, which is the same rule the rest of the project follows.
- `Scripts/quality.sh` deliberately splits responsibility: **swift-format owns style, SwiftLint owns
  size and complexity.** Two tools both configured for style would produce arguments in every diff.
- The metrics are **enforcing**, not advisory: `swiftlint --strict` fails the build on a warning. The
  thresholds in the synced config were set against Aemi's own tree, so a package with genuinely
  different shapes may need its own thresholds — but they must then be a deliberate, recorded change
  and not a quiet edit that lets the gate rot.
- SwiftLint is excluded from `Tests/` in the synced config, matching Aemi's own roll-out. Test files
  are therefore not currently gated on size.