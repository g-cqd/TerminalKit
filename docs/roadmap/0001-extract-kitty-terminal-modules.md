---
status: not-started
blocked-by:
date: 2026-10-18
---

# 0001 — Extract the Kitty terminal modules into TerminalKit

Move the terminal stack out of Atelier into this package, renaming `Kitty*` to `TerminalKit*`.

**Scope, measured by probe — not by module name.** Six modules, 6,263 lines:

| Module | LOC | From |
|---|---|---|
| `KittyStyle` | 58 | `Apps/KittyCode` |
| `KittyTerminal` | 573 | `Apps/KittyCode` |
| `KittyCodecs` | 1,815 | `Apps/KittyCode` |
| `AtelierText` | 1,851 | `Packages/AtelierCore` |
| `KittyRenderer` | 1,142 | `Apps/KittyCode` |
| `KittyInput` | 824 | `Apps/KittyCode` |

`KittyEditor` (10,890 lines, sixteen dependencies) is **outside** the seam: it is the application tier.

**Destination.** `TerminalKitStyle`, `TerminalKitIO` (from `KittyTerminal`), `TerminalKitCodecs`,
`TerminalKitText` (from `AtelierText`), `TerminalKitRender`, `TerminalKitInput`. `TerminalKitCore`
already exists.

**Dependency.** This is where `AemiKernel` first becomes real: `KittyCodecs` and `KittyInput` both
import it. Add it here, with the move, and not before.

**Done when:** Atelier builds and its existing tests pass against TerminalKit; no `Kitty*` terminal
module remains in Atelier; the six modules are exported.

**Slicing.** `AtelierText` comes from `AtelierCore` and touches a different package, so it moves in its
own commit. Behaviour changes never ride along with a move: the DEC 2026 wrapping and the zero-copy
writes in the renderer are the load-bearing parts and must arrive unchanged.