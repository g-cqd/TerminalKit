---
status: accepted
date: 2026-10-18
---

# 0001 — TerminalKit is its own repository

## Context

The terminal stack began as three modules inside Atelier's `Apps/KittyCode`. It was first proposed as a
group of targets inside Aemi, and `AemiTerminalCore` was landed there (Aemi `03ac1d5`) before the
placement was questioned.

Three consumers need this stack: `Apps/KittyCode`, Atelier, and `ask`. Where it lives decides what
each of them depends on.

## The probes

**Probe 1 — is terminal one of Aemi's existing categories?** Aemi's manifest states its purpose as the
kernel package, and its targets divide into kernel runtime tiers (`AemiKernel`, `AemiText`, `AemiIO`,
`AemiMetrics`, `AemiRuntime`, `AemiUnicode`, `AemiKernels`, `AemiMacroSupport`) and application tiers
(`AemiCore`, `AemiUI`, `AemiTesting`). The manifest explicitly keeps the two apart.

**REFUTED as a fit.** Terminal is neither. It is a third concern — escape-sequence grammar, capability
negotiation, a reset lifecycle — and adding it stretches a boundary Aemi already has to defend.

**Probe 2 — what does a consumer of `AemiKernel` actually resolve?** `grep` of Aemi's `.package(url:)`
declarations: **swift-syntax 603..<605**, swift-collections, swift-system, swift-docc-plugin,
benchmark.

**CONFIRMED, with a limit.** `AemiKernel` is itself zero-dependency, but SwiftPM resolves a package's
whole manifest regardless of which target is linked. A consumer wanting only a byte kernel still
resolves the swift-syntax macro tree. This is a real cost — and it is only *partly* relieved here,
because the extraction from Atelier will make TerminalKit depend on `AemiKernel`, and therefore on Aemi.
Recorded so the saving is not overstated.

**Probe 3 — is Aemi a steady release target?** `git tag` in the Aemi clone returns **zero tags**.

**CONFUTED that it is.** Terminal work is moving fastest of anything in the ecosystem; making it wait on
a repository with no releases is a real drag.

## Options

1. **`TerminalKit`, its own repository.** Independent cadence and manifest; the stack belongs to no
   single host application.
2. `AemiTerminal` inside Aemi. Focused code, but stretches Aemi's stated scope and inherits its cadence.
3. Leave it in Atelier. `ask` would then depend on an application repository to get a terminal.

## Decision

**Option 1: `TerminalKit`, its own repository**, starting as a straight move of `AemiTerminalCore` and
the oracle model, both landed in Aemi within the last two commits.

**Named `TerminalKit`, not `AemiTerminal`.** Once the package has its own repository, an `Aemi` prefix
asserts an ownership that no longer holds, and the name should not imply that the terminal stack
belongs to Aemi any more than Aemi belongs to the terminal stack.

## Consequences

- The terminal code leaves Aemi immediately rather than later: `AemiTerminalCore` and the oracle are
  reverted from Aemi rather than left duplicated.
- TerminalKit depends on Aemi **only** once the extraction introduces a real need for `AemiKernel`.
  Today it has **zero external dependencies**, and adding an unused one would be a liability.
- A new repository must recreate the quality tooling Aemi provides — swift-format, SwiftLint
  configuration, and CI. This is the honest cost of the separation.
- The GitHub remote is **not yet created**, so the repository exists locally only.