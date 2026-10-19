internal import Synchronization
internal import TerminalKitCodecs
internal import TerminalKitCore
public import TerminalKitIO

/// Terminal modes entered as one unit and left as one unit, on every exit path (roadmap 0010, ADR-0019).
///
/// Entering takes raw mode and then writes every mode in one write. Leaving writes, in one write:
/// - the end of any synchronized update a frame left open;
/// - each mode turned off in the reverse order it was turned on, so the kitty keyboard flags are popped
///   while still on the alternate screen, whose stack they were pushed on;
/// - tier 1 of the reset ladder, for anything the program turned on outside the session;
///
/// then restores `termios`. Leaving is idempotent and safe from any thread, so the signal path and the
/// normal path can both call it and the terminal sees one exit.
///
/// With ``KeyboardProtocolSupport/probe`` the entry write also asks for the keyboard flags and the primary
/// device attributes, and waits for neither (ADR-0020). Pass input events to ``observe(_:)``: the replies
/// arrive there, and the flags are pushed when the answer says the terminal supports them.
public final class TerminalSession: Sendable {
    private enum Phase {
        case ready, entered, left
    }

    private enum Keyboard {
        /// No flags wanted, or the terminal does not support them.
        case off
        /// Flags wanted, and the answer not yet in.
        case asking
        /// Flags pushed; leaving pops them.
        case pushed
    }

    private struct State {
        var phase = Phase.ready
        var keyboard: Keyboard
        /// Whether the device-attributes reply that ends the probe is still to come.
        var awaitingAttributes: Bool
    }

    private let connection: any TerminalConnection
    private let requested: TerminalModes
    private let keyboardProtocol: KeyboardProtocolSupport
    private let state: Mutex<State>

    /// - Parameters:
    ///   - connection: the terminal; nothing is written until ``enter()``.
    ///   - modes: the modes wanted.
    ///   - keyboardProtocol: what is known of the kitty keyboard protocol. Flags are pushed on entry only
    ///     when ``KeyboardProtocolSupport/supported``, and after a reply when
    ///     ``KeyboardProtocolSupport/probe``.
    public init(connection: any TerminalConnection, modes: TerminalModes, keyboardProtocol: KeyboardProtocolSupport) {
        self.connection = connection
        self.requested = modes
        self.keyboardProtocol = modes.kittyKeyboardFlags == 0 ? .unsupported : keyboardProtocol
        let keyboard: Keyboard =
            switch self.keyboardProtocol {
                case .supported: .pushed
                case .probe: .asking
                case .unsupported: .off
            }
        state = Mutex(State(keyboard: keyboard, awaitingAttributes: keyboard == .asking))
    }

    /// The modes in force: those asked for, with the kitty keyboard flags only while they are pushed.
    public var modes: TerminalModes {
        var current = requested
        if state.withLock({ $0.keyboard }) != .pushed { current.kittyKeyboardFlags = 0 }
        return current
    }

    /// Whether the Escape key arrives as `CSI 27 u`, so a lone `ESC` byte always begins a sequence. Keep
    /// ``InputSource/escapeIsUnambiguous`` equal to it.
    public var escapeIsUnambiguous: Bool { modes.kittyKeyboardFlags & KittyKeyboardFlags.disambiguate != 0 }

    /// Takes raw mode, then enters every mode in one write. A second call does nothing.
    ///
    /// - Throws: the connection's error. If the write fails, the session leaves before rethrowing, so
    ///   raw mode is not left behind.
    public func enter() throws(TerminalError) {
        let shouldEnter = state.withLock { state in
            guard state.phase == .ready else { return false }
            state.phase = .entered
            return true
        }
        guard shouldEnter else { return }
        do {
            try connection.enterRawMode()
        } catch {
            state.withLock { $0.phase = .ready }
            throw error
        }
        do {
            try connection.writeContiguous(enterBytes)
        } catch {
            leave()
            throw error
        }
    }

    /// Takes a probe reply out of the input, and pushes the keyboard flags if it says to.
    ///
    /// Call it with every input event, from the context that writes frames, so the push never lands
    /// inside a frame's bytes.
    ///
    /// - Returns: `true` when `event` was a reply to the session's own query, which the caller drops.
    public func observe(_ event: InputEvent) -> Bool {
        guard case .unknown(let bytes) = event, let reply = ProbeReply(bytes) else { return false }
        let push = state.withLock { state -> Bool? in
            guard state.awaitingAttributes else { return nil }
            switch reply {
                case .keyboardFlags:
                    // Only while asking and still entered: a reply that outlives the session pushes nothing.
                    guard state.keyboard == .asking, state.phase == .entered else { return false }
                    state.keyboard = .pushed
                    return true
                case .deviceAttributes:
                    state.awaitingAttributes = false
                    if state.keyboard == .asking { state.keyboard = .off }
                    return false
            }
        }
        guard let push else { return false }
        if push {
            try? connection.writeContiguous(
                ContiguousArray(EscapeSequences.pushKeyboardMode(flags: requested.kittyKeyboardFlags)))
        }
        return true
    }

    /// Leaves every mode and restores `termios`, once. Failures are ignored: a terminal that cannot be
    /// written to still needs its `termios` back, and there is nobody to report to on the way out.
    public func leave() {
        let bytes = state.withLock { state -> ContiguousArray<UInt8>? in
            guard state.phase == .entered else { return nil }
            state.phase = .left
            return leaveBytes(keyboardPushed: state.keyboard == .pushed)
        }
        guard let bytes else { return }
        try? connection.writeContiguous(bytes)
        try? connection.restoreMode()
    }

    /// Runs `body` inside a session, leaving it however `body` ends.
    public static func run<Result>(
        on connection: any TerminalConnection,
        modes: TerminalModes,
        keyboardProtocol: KeyboardProtocolSupport,
        isolation: isolated (any Actor)? = #isolation,
        _ body: (TerminalSession) async throws -> Result
    ) async throws -> Result {
        let session = TerminalSession(connection: connection, modes: modes, keyboardProtocol: keyboardProtocol)
        try session.enter()
        defer { session.leave() }
        return try await body(session)
    }

    // MARK: - Bytes

    /// Every requested mode, in the order they are turned on, then the keyboard query when probing.
    var enterBytes: ContiguousArray<UInt8> {
        var bytes = ContiguousArray<UInt8>()
        if requested.alternateScreen {
            bytes.append(contentsOf: EscapeSequences.enterAlternateScreen)
            bytes.append(contentsOf: EscapeSequences.clearScreen)
        }
        if requested.hiddenCursor { bytes.append(contentsOf: EscapeSequences.hideCursor) }
        if requested.bracketedPaste { bytes.append(contentsOf: EscapeSequences.enableBracketedPaste) }
        if requested.focusEvents { bytes.append(contentsOf: EscapeSequences.enableFocusEvents) }
        if requested.mouse { bytes.append(contentsOf: EscapeSequences.enableMouseSGR) }
        switch keyboardProtocol {
            case .supported:
                bytes.append(contentsOf: EscapeSequences.pushKeyboardMode(flags: requested.kittyKeyboardFlags))
            case .probe:
                bytes.append(contentsOf: ProbeReply.query)
            case .unsupported:
                break
        }
        return bytes
    }

    /// The open update ended, every mode turned off in reverse, then tier 1 of the reset ladder.
    func leaveBytes(keyboardPushed: Bool) -> ContiguousArray<UInt8> {
        var bytes = ContiguousArray<UInt8>(EscapeSequences.endSyncUpdate)
        if keyboardPushed { bytes.append(contentsOf: EscapeSequences.popKeyboardMode) }
        if requested.mouse { bytes.append(contentsOf: EscapeSequences.disableMouseSGR) }
        if requested.focusEvents { bytes.append(contentsOf: EscapeSequences.disableFocusEvents) }
        if requested.bracketedPaste { bytes.append(contentsOf: EscapeSequences.disableBracketedPaste) }
        if requested.hiddenCursor { bytes.append(contentsOf: EscapeSequences.showCursor) }
        if requested.alternateScreen { bytes.append(contentsOf: EscapeSequences.leaveAlternateScreen) }
        bytes.append(contentsOf: TerminalResetLadder.escapeBytes(for: .selectiveCleanup))
        return bytes
    }
}
