---
status: accepted
date: 2026-10-18
---

# 0007 — Generic tools are promoted to Aemi

## Context

The ecosystem began moving code into packages for the wrong reason: because two consumers needed it.
That produced TerminalKit, which is right. But the reasoning generalises further than the example did.

Aemi is the kernel package. Anything generic enough that a second consumer is *plausible* — a byte
kernel, a text primitive, a process seam, a test kit — belongs there rather than inside whichever
application happened to need it first.

## The evidence that forced it

Enforcing the runtime principle — fewest allocations, measured rather than asserted — meant reaching
for Aemi's `expectAllocations`. It could not be used. `AemiTestKit` transitively needs
`CAemiTestKitMalloc`, which needs the `CAemiKernels` C target, and that target is **not exposed as a
product**. So:

- importing `AemiTestKit` from a dependent resolves fine in a scratch package, but
- a test target inside a package that also uses `AemiKernel` fails with
  `unable to resolve module dependency: 'CAemiKernels'`,
- and declaring `AemiKernel` explicitly turns it into a link failure instead.

The measurement instrument the ecosystem already owns is unreachable from inside a consumer. That is a
packaging defect in a package the whole ecosystem depends on, and the fix belongs in Aemi rather than
in a workaround inside TerminalKit.

## Decision

**A tool that is not specific to one application is promoted to Aemi.** This is a standing rule for
anything encountered anywhere in the ecosystem, not a one-off decision about TerminalKit. The test is
whether a second consumer is plausible, not whether one exists today.

The consequence is accepted rather than avoided: promoting something into Aemi changes a package other
projects depend on, so it is measured, reviewed, and pinned by dependents like any other change.

## Consequences

- **`CAemiKernels` must become a product**, or the C targets must be reachable through the products
  that need them. Until then `expectAllocations` cannot be used by a dependent that also uses
  `AemiKernel`. This is now the first entry on the list.
- **TerminalKit's footprint guard is blocked**, not deleted. `FootprintBudgetTests` is held at
  `/tmp/FootprintBudgetTests.swift.blocked` in this session because `KeyboardDecoder` lives in
  `TerminalKitCodecs`, which reaches `AemiKernel` and so hits the defect. A local
  `ProcessFootprint` was written as a substitute and is committed; the test that uses it waits only on
  the product being reachable.
- A measurement must never be quietly replaced by a weaker one to get past a packaging problem. The
  substitute instrument is stated as coarser, and the blocked test is named.

## The rule going forward

When a generic helper appears anywhere — in `ask`, in TerminalKit, in Atelier — the question is not
"does this project need it" but "would Aemi's scope serve it better than this one package". Usually the
answer is yes, and the code goes to Aemi and comes back as a dependency.