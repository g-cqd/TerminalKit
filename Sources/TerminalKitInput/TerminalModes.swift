/// The terminal modes a full-screen program wants for its whole run.
///
/// A ``TerminalSession`` enters them together and leaves them together, so no program has to remember
/// each sequence. ask forgot one: it never enabled bracketed paste, so a pasted newline pressed Enter.
public struct TerminalModes: Sendable, Equatable {
    /// The alternate screen (`?1049`), cleared on entry; the user's scrollback is untouched.
    public var alternateScreen: Bool
    /// The cursor hidden (`?25l`); a render pipeline shows it where it wants it.
    public var hiddenCursor: Bool
    /// Bracketed paste (`?2004`): a paste arrives as one event, so its newlines do not press Enter.
    public var bracketedPaste: Bool
    /// Focus reports (`?1004`): `ESC [ I` and `ESC [ O` when the window gains and loses focus.
    public var focusEvents: Bool
    /// Mouse reports for clicks and drags, SGR-encoded (`?1000`, `?1002`, `?1006`).
    public var mouse: Bool
    /// Kitty keyboard protocol flags to push (`CSI > flags u`), or zero for none. Pushed only when the
    /// terminal answered the keyboard probe (ADR-0014); see ``KittyKeyboardFlags``.
    public var kittyKeyboardFlags: UInt8

    public init(
        alternateScreen: Bool = false,
        hiddenCursor: Bool = false,
        bracketedPaste: Bool = false,
        focusEvents: Bool = false,
        mouse: Bool = false,
        kittyKeyboardFlags: UInt8 = 0
    ) {
        self.alternateScreen = alternateScreen
        self.hiddenCursor = hiddenCursor
        self.bracketedPaste = bracketedPaste
        self.focusEvents = focusEvents
        self.mouse = mouse
        self.kittyKeyboardFlags = kittyKeyboardFlags
    }

    /// The modes an interactive screen like ask's needs: alternate screen, hidden cursor, bracketed paste,
    /// and unambiguous Escape where the terminal supports it.
    public static let fullScreen = TerminalModes(
        alternateScreen: true, hiddenCursor: true, bracketedPaste: true,
        kittyKeyboardFlags: KittyKeyboardFlags.disambiguate)
}

/// Flags of the kitty keyboard protocol.
public enum KittyKeyboardFlags {
    /// Keys that are ambiguous in the legacy encoding, Escape among them, arrive as `CSI … u`. A lone
    /// `ESC` byte is then always the start of a sequence, never the Escape key.
    public static let disambiguate: UInt8 = 1
}

/// What a session knows about the terminal's kitty keyboard protocol when it is created.
public enum KeyboardProtocolSupport: Sendable, Equatable {
    /// The terminal answered a keyboard query already; the flags are pushed on entry.
    case supported
    /// The terminal does not support it, or the flags are not wanted; nothing is pushed or asked.
    case unsupported
    /// Ask on entry, without waiting, and push the flags if the answer says so (``TerminalSession/observe(_:)``).
    case probe
}
