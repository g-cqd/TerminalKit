internal import Foundation
internal import TerminalKitCodecs

/// Which terminal the program is running in, read from its environment.
///
/// What each one does was measured (TerminalKit ADR-0028): a terminal the kit has not measured is ``unknown`` and gets the
/// conservative behaviour.
public enum TerminalIdentity: Sendable, Equatable {
    case kitty
    case ghostty
    case wezterm
    case appleTerminal
    /// Not one of the four measured, or inside something that hides it, such as tmux.
    case unknown

    /// Reads the terminal from the variables it sets: `TERM`, `TERM_PROGRAM` and, for kitty, `KITTY_WINDOW_ID`.
    public init(environment: [String: String]) {
        let program = environment["TERM_PROGRAM"] ?? ""
        let term = environment["TERM"] ?? ""
        if program == "tmux" || environment["TMUX"] != nil {
            self = .unknown
        } else if program == "Apple_Terminal" {
            self = .appleTerminal
        } else if program == "WezTerm" {
            self = .wezterm
        } else if program == "ghostty" || term == "xterm-ghostty" {
            self = .ghostty
        } else if term == "xterm-kitty" || environment["KITTY_WINDOW_ID"] != nil {
            self = .kitty
        } else {
            self = .unknown
        }
    }

    /// Whether the terminal takes an OSC 52 clipboard write: yes for kitty, Ghostty and WezTerm, which landed payloads up to 1 MB
    /// exactly, and no for Terminal.app, which ignored every one. Nil for a terminal that was not measured.
    public var takesClipboardWrites: Bool? {
        switch self {
            case .kitty, .ghostty, .wezterm: true
            case .appleTerminal: false
            case .unknown: nil
        }
    }

    /// Whether the terminal drops the first clipboard write after a window opens, which WezTerm did in every run.
    public var dropsTheFirstClipboardWrite: Bool { self == .wezterm }

    /// The key that gives the terminal its own selection back while the mouse is reported to the program: Shift in kitty, Ghostty and
    /// WezTerm, which do not pass it on, and fn in Terminal.app, which passes Shift through like any modifier. Nil if unmeasured.
    public var nativeSelectionKey: String? {
        switch self {
            case .kitty, .ghostty, .wezterm: "Shift"
            case .appleTerminal: "fn"
            case .unknown: nil
        }
    }
}

/// What to do to put some text on the clipboard: bytes for the terminal, and whether the host should also use its own pasteboard.
public struct ClipboardPlan: Sendable, Equatable {
    /// How the plan turned out, for a status line or a test.
    public enum Outcome: Sendable, Equatable {
        /// An OSC 52 write is to be sent, and nothing else.
        case terminal
        /// The host's pasteboard is to be used, and no OSC 52 write sent.
        case pasteboard
        /// Both: for a terminal that was not measured, so that one of them lands.
        case both
        /// The text is too large for OSC 52 and there is no local pasteboard to fall back on.
        case tooLarge
        /// Nothing can put it on the clipboard: a terminal that ignores OSC 52 over a remote connection.
        case unavailable
        /// There was nothing to copy, and the clipboard is left as it is.
        case nothing
    }

    /// Bytes to write to the terminal, or nil.
    public var terminal: [UInt8]?
    /// Whether the host should write `text` to its own pasteboard.
    public var usePasteboard: Bool
    public var outcome: Outcome
}

/// Plans each copy, with the memory it needs: whether a first write has been made.
///
/// It decides and does nothing, so a host writes the bytes through its own connection and runs its own pasteboard command, and the
/// decisions are testable without a terminal. The rules are ADR-0028's:
/// - OSC 52 is sent unless the terminal is known to ignore it, or the text is over ``maximumTerminalBytes``.
/// - The host's pasteboard is used when the terminal is not known to take OSC 52 (so Terminal.app and unknown terminals), or the
///   text is too big for it, but never over a remote connection, where the pasteboard is the remote machine's.
/// - On a terminal that drops the first write (WezTerm), the first one is sent twice.
public struct ClipboardWriter: Sendable {
    /// The largest payload measured to land exactly in kitty, Ghostty and WezTerm.
    public static let maximumTerminalBytes = 1_000_000

    public var identity: TerminalIdentity
    public var isRemote: Bool
    private var writes = 0

    public init(identity: TerminalIdentity, isRemote: Bool = false) {
        self.identity = identity
        self.isRemote = isRemote
    }

    /// A writer for the terminal this process is in, read from `environment` (`SSH_CONNECTION` or `SSH_TTY` mean remote).
    public init(environment: [String: String]) {
        self.init(
            identity: TerminalIdentity(environment: environment),
            isRemote: environment["SSH_CONNECTION"] != nil || environment["SSH_TTY"] != nil)
    }

    /// Plans copying `text`.
    public mutating func plan(copying text: String) -> ClipboardPlan {
        guard !text.isEmpty else { return ClipboardPlan(terminal: nil, usePasteboard: false, outcome: .nothing) }
        let size = text.utf8.count
        let oversized = size > Self.maximumTerminalBytes
        let sendToTerminal = identity.takesClipboardWrites != false && !oversized
        let usePasteboard = !isRemote && (identity.takesClipboardWrites != true || oversized)

        var bytes: [UInt8]?
        if sendToTerminal {
            let one = EscapeSequences.setClipboard(Data(text.utf8).base64EncodedString())
            bytes = identity.dropsTheFirstClipboardWrite && writes == 0 ? one + one : one
            writes += 1
        }
        let outcome: ClipboardPlan.Outcome =
            switch (sendToTerminal, usePasteboard) {
                case (true, true): .both
                case (true, false): .terminal
                case (false, true): .pasteboard
                case (false, false): oversized ? .tooLarge : .unavailable
            }
        return ClipboardPlan(terminal: bytes, usePasteboard: usePasteboard, outcome: outcome)
    }
}
