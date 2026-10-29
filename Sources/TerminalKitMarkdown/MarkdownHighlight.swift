public import TerminalKitStyle

/// A run of bytes of one code line in a style of its own, as a ``MarkdownCodeHighlighter`` finds it.
public struct MarkdownHighlight: Sendable, Equatable {
    /// UTF-8 offsets in the line, as the line was given.
    public var bytes: Range<Int>
    /// Drawn over the theme's code block style: what it sets wins.
    public var style: Style

    /// `style` over `bytes`.
    public init(bytes: Range<Int>, style: Style) {
        self.bytes = bytes
        self.style = style
    }
}
