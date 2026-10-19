internal import Darwin
import Testing

@testable import TerminalKitIO

/// Entering and leaving raw mode must never wait on the terminal's output.
///
/// `tcsetattr` with `TCSAFLUSH` or `TCSADRAIN` waits until queued output has drained. Probed on macOS 27
/// (docs/diary/2026-10-19-03.md), it waits forever in two cases: output stopped by Ctrl-S or `TCOOFF`, and
/// an emulator that has stopped reading. A program that hangs on its way out leaves the terminal raw.
@Suite("Raw mode never waits on output")
struct TerminalRestoreTests {
    private let frame = Array("frame".utf8)

    @Test func `restoring the terminal does not wait behind output the terminal stopped`() throws {
        let pty = try PseudoTerminal()
        let connection = POSIXTerminalConnection(fileDescriptor: pty.terminal)
        try connection.enterRawMode()
        _ = pty.outputAvailable()
        tcflow(pty.terminal, TCOOFF)
        try connection.write(frame)

        try connection.restoreMode()

        // Output flows again, so the shell the user returns to is not frozen behind a stop.
        #expect(pty.outputAvailable() == frame)
    }

    @Test func `restoring the terminal does not wait for an emulator that stopped reading`() throws {
        let pty = try PseudoTerminal()
        let connection = POSIXTerminalConnection(fileDescriptor: pty.terminal)
        try connection.enterRawMode()
        try connection.write(frame)

        try connection.restoreMode()

        // Nothing was discarded: the emulator still receives the frame when it reads.
        #expect(pty.outputAvailable() == frame)
    }

    @Test func `entering raw mode does not wait behind output the terminal stopped`() throws {
        let pty = try PseudoTerminal()
        tcflow(pty.terminal, TCOOFF)
        _ = frame.withUnsafeBytes { unsafe Darwin.write(pty.terminal, $0.baseAddress, $0.count) }
        let connection = POSIXTerminalConnection(fileDescriptor: pty.terminal)

        try connection.enterRawMode()
        defer { try? connection.restoreMode() }

        // In raw mode Ctrl-Q is a key, not a resume, so a stop left in place would never be lifted.
        #expect(pty.outputAvailable() == frame)
    }

    @Test func `restoring the terminal discards typeahead the program never read`() throws {
        // TCSAFLUSH discarded unread input; replacing it must keep that, or a late reply to a probe, or keys
        // typed while the program exits, would land in the user's shell.
        let pty = try PseudoTerminal()
        let connection = POSIXTerminalConnection(fileDescriptor: pty.terminal)
        try connection.enterRawMode()
        pty.type(Array("typed".utf8))

        try connection.restoreMode()

        // Canonical input reads nothing until a newline, so look at the queue in non-canonical mode.
        var settings = termios()
        tcgetattr(pty.terminal, &settings)
        settings.c_lflag &= ~tcflag_t(ICANON | ECHO)
        tcsetattr(pty.terminal, TCSANOW, &settings)
        #expect(pty.inputAvailable().isEmpty)
    }
}
