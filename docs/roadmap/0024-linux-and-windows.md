---
status: not-started
blocked-by: []
date: 2026-10-29
---

# 0024 — Building and running on Linux (Windows later)

`Package.swift` declares macOS 26 only. What stops a Linux build: `TerminalKitIO` terminal connection and termios calls (Darwin names),
`SignalHandler` and `CTerminalSignals` (kqueue versus signalfd or `sigwaitinfo`), `InputSource`'s kqueue-based waker, `SystemAppearance` (no
notification; a freedesktop portal setting is the equivalent), clipboard (`pbcopy` has no equivalent; OSC 52 only, or `wl-copy` and `xclip`).

Order: make the targets that are pure Swift compile first (`Style`, `Text`, `Codecs`, `Render` without I/O), then `IO` and `Input` behind
`#if os(Linux)` seams, with the CI of this package running both. A Windows console is a separate design (ConPTY, VT mode) and not planned.
