# TerminalKit

The terminal stack for the Aemi ecosystem, shared by Atelier's KittyCode and
[`ask`](https://github.com/ask).

A package of its own rather than a target inside Aemi. Terminal is neither a kernel runtime primitive
nor an application tier — it is a third concern, with its own escape-sequence grammar, capability
negotiation and release cadence. See
[ADR-0001](docs/adr/0001-terminalkit-is-its-own-repository.md).

## Read this first

**[docs/WHITE-PAPER.md](docs/WHITE-PAPER.md)** — the rules this package runs on, led by the evidence
rule: every claim is challenged and backed by an actual probe before it is adopted, and there is no
place for an assumption.

## Layout

| Path | What |
|---|---|
| `docs/WHITE-PAPER.md` | The rules, and the probe ledger |
| `docs/adr/` | One decision per file |
| `docs/roadmap/` | One entry per file |
| `docs/diary/` | The working log, capped at 256 lines per file |

## Products

| Product | What |
|---|---|
| `TerminalKitCore` | Escape sequences and the tiered reset ladder. No file descriptor, no `termios`, no clock |
| `TerminalKitTestSupport` | The oracle terminal model, so a consumer can test its own terminal layer the same way |
| `TerminalKit` | Umbrella re-exporting the core. Test support is deliberately **not** re-exported |

## Status

Early. `TerminalKitCore` holds the reset ladder; the rest of the stack has not been extracted yet.
The GitHub remote does not exist — this repository is local only.

## Building

```sh
swift build -c release
swift test  -c release
```

Release only. A debug build measures a program nobody ships.

## How the reset ladder is verified

Three independent levels, because they are three different claims:

1. **Byte-exact tests** — the encoder emits exactly the sequence intended.
2. **Oracle tests** — a model of the terminal, written from the specification, agrees with those bytes.
3. **Real-emulator tests** — **still owed.** A model is not a terminal.

The third level has not run: kitty 0.49.2 is installed but no instance is reachable from a
non-controlling-TTY session. See
[roadmap 0002](docs/roadmap/0002-verify-against-a-real-terminal.md).