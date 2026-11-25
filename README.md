# TerminalKit

Modular Swift 6 terminal stack for macOS: raw-mode TTY I/O, escape-sequence codecs, input/signal routing, rope-backed Unicode text buffers, double-buffered cell rendering, and declarative terminal UI components.

## Requirements

- Swift 6.4+ (Swift 6 language mode, strict memory safety)
- macOS 26+

## Installation

```swift
dependencies: [
    .package(url: "https://github.com/g-cqd/TerminalKit.git", branch: "main")
]
```

## Products

| Product | Description |
| --- | --- |
| `TerminalKitCore` | Core reset sequences and shared terminal constants |
| `TerminalKitIO` | Terminal connections, raw mode, and geometry |
| `TerminalKitStyle` | Style and color value types |
| `TerminalKitCodecs` | Escape encoders and keyboard/mouse decoders |
| `TerminalKitInput` | Input routing, async streams, signal handling, and terminal sessions |
| `TerminalKitText` | Rope-backed text operations and display width metrics |
| `TerminalKitRender` | Screen buffers, frame diffing, and synchronized output |
| `TerminalKitUI` | Declarative terminal layout and interactive components |

## Documentation

- [Architecture Decisions](docs/adr/)
- [Contributing](CONTRIBUTING.md)
- [Security](SECURITY.md)

## License

[MIT](LICENSE)
