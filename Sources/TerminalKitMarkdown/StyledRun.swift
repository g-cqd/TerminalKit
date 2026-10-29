public import TerminalKitStyle

/// Text drawn in one style, and the bytes of the Markdown source it shows.
public struct StyledRun: Sendable, Equatable {
    /// What is drawn.
    public var text: String
    /// How it is drawn.
    public var style: Style
    /// The source bytes the text shows, or nil for chrome the renderer added: a list marker, a quote bar, padding, a rule, a link target.
    ///
    /// A run of plain text shows its source byte for byte; a character reference shows its decoded character, and a tab in code shows spaces,
    /// over the range of what they decode.
    public var source: Range<Int>?

    /// A run of `text` in `style`, showing `source`.
    public init(_ text: String, style: Style, source: Range<Int>? = nil) {
        self.text = text
        self.style = style
        self.source = source
    }
}
