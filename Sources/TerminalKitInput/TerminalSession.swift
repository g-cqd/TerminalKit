internal import Synchronization
internal import TerminalKitCodecs
internal import TerminalKitCore
public import TerminalKitIO

/// Terminal modes entered as one unit and left as one unit, on every exit path (roadmap 0010).
///
/// Entering takes raw mode and then writes every mode in one write. Leaving writes, in one write:
/// - the end of any synchronized update a frame left open;
/// - each mode turned off in the reverse order it was turned on, so the kitty keyboard flags are popped
///   while still on the alternate screen, whose stack they were pushed on;
/// - tier 1 of the reset ladder, for anything the program turned on outside the session;
///
/// then restores `termios`. Leaving is idempotent and safe from any thread, so the signal path and the
/// normal path can both call it and the terminal sees one exit.
public final class TerminalSession: Sendable {
    private enum Phase {
        case ready, entered, left
    }

    /// The modes this session enters: those asked for, less the kitty keyboard flags when the terminal
    /// did not answer the keyboard probe.
    public let modes: TerminalModes

    private let connection: any TerminalConnection
    private let phase = Mutex(Phase.ready)

    /// - Parameters:
    ///   - connection: the terminal; nothing is written until ``enter()``.
    ///   - modes: the modes wanted.
    ///   - keyboardProtocolSupported: whether the terminal answered the kitty keyboard query
    ///     (`ProbedCapabilities.keyboardProtocolFlags != nil`). Without it no flags are pushed.
    public init(connection: any TerminalConnection, modes: TerminalModes, keyboardProtocolSupported: Bool) {
        var granted = modes
        if !keyboardProtocolSupported { granted.kittyKeyboardFlags = 0 }
        self.connection = connection
        self.modes = granted
    }

    /// Whether the Escape key arrives as `CSI 27 u`, so a lone `ESC` byte always begins a sequence. Pass it
    /// to ``InputSource/init(connection:escapeIsUnambiguous:)``.
    public var escapeIsUnambiguous: Bool { modes.kittyKeyboardFlags & KittyKeyboardFlags.disambiguate != 0 }

    /// Takes raw mode, then enters every mode in one write. A second call does nothing.
    ///
    /// - Throws: the connection's error. If the write fails, the session leaves before rethrowing, so
    ///   raw mode is not left behind.
    public func enter() throws(TerminalError) {
        let shouldEnter = phase.withLock { phase in
            guard phase == .ready else { return false }
            phase = .entered
            return true
        }
        guard shouldEnter else { return }
        do {
            try connection.enterRawMode()
        } catch {
            phase.withLock { $0 = .ready }
            throw error
        }
        do {
            try connection.writeContiguous(enterBytes)
        } catch {
            leave()
            throw error
        }
    }

    /// Leaves every mode and restores `termios`, once. Failures are ignored: a terminal that cannot be
    /// written to still needs its `termios` back, and there is nobody to report to on the way out.
    public func leave() {
        let shouldLeave = phase.withLock { phase in
            guard phase == .entered else { return false }
            phase = .left
            return true
        }
        guard shouldLeave else { return }
        try? connection.writeContiguous(leaveBytes)
        try? connection.restoreMode()
    }

    /// Runs `body` inside a session, leaving it however `body` ends.
    public static func run<Result>(
        on connection: any TerminalConnection,
        modes: TerminalModes,
        keyboardProtocolSupported: Bool,
        isolation: isolated (any Actor)? = #isolation,
        _ body: (TerminalSession) async throws -> Result
    ) async throws -> Result {
        let session = TerminalSession(
            connection: connection, modes: modes, keyboardProtocolSupported: keyboardProtocolSupported)
        try session.enter()
        defer { session.leave() }
        return try await body(session)
    }

    // MARK: - Bytes

    /// Every mode in ``modes``, in the order they are turned on.
    var enterBytes: ContiguousArray<UInt8> {
        var bytes = ContiguousArray<UInt8>()
        if modes.alternateScreen {
            bytes.append(contentsOf: EscapeSequences.enterAlternateScreen)
            bytes.append(contentsOf: EscapeSequences.clearScreen)
        }
        if modes.hiddenCursor { bytes.append(contentsOf: EscapeSequences.hideCursor) }
        if modes.bracketedPaste { bytes.append(contentsOf: EscapeSequences.enableBracketedPaste) }
        if modes.focusEvents { bytes.append(contentsOf: EscapeSequences.enableFocusEvents) }
        if modes.mouse { bytes.append(contentsOf: EscapeSequences.enableMouseSGR) }
        if modes.kittyKeyboardFlags != 0 {
            bytes.append(contentsOf: EscapeSequences.pushKeyboardMode(flags: modes.kittyKeyboardFlags))
        }
        return bytes
    }

    /// The open update ended, every mode turned off in reverse, then tier 1 of the reset ladder.
    var leaveBytes: ContiguousArray<UInt8> {
        var bytes = ContiguousArray<UInt8>(EscapeSequences.endSyncUpdate)
        if modes.kittyKeyboardFlags != 0 { bytes.append(contentsOf: EscapeSequences.popKeyboardMode) }
        if modes.mouse { bytes.append(contentsOf: EscapeSequences.disableMouseSGR) }
        if modes.focusEvents { bytes.append(contentsOf: EscapeSequences.disableFocusEvents) }
        if modes.bracketedPaste { bytes.append(contentsOf: EscapeSequences.disableBracketedPaste) }
        if modes.hiddenCursor { bytes.append(contentsOf: EscapeSequences.showCursor) }
        if modes.alternateScreen { bytes.append(contentsOf: EscapeSequences.leaveAlternateScreen) }
        bytes.append(contentsOf: TerminalResetLadder.escapeBytes(for: .selectiveCleanup))
        return bytes
    }
}
