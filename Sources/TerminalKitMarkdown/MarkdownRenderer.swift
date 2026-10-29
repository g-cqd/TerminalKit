public import AemiMarkdown

/// Draws a Markdown document as rows of styled text, for any width: what a host shows in a terminal without turning a tree into escape
/// sequences itself (roadmap 0022).
///
/// Lay a document out block by block: a top-level block's rows depend on the block and the width only, so a host keeps the rows of each final
/// block (``MarkdownBlock/isFinal``) by its identity and lays out again only the open one as a streamed answer grows. Each run names the source
/// bytes it shows, so a selection can copy the Markdown it covers.
///
/// ```swift
/// var renderer = MarkdownRenderer()
/// let document = MarkdownParser.parse(Array("# Title\n\nSome **bold** text.\n".utf8))
/// for block in document.topLevelBlocks {
///     let rows = renderer.lines(of: block, in: document, width: 80)
/// }
/// ```
public struct MarkdownRenderer: Sendable {
    /// The styles and glyphs rows are drawn in.
    public var theme: MarkdownTheme
    /// What links become.
    public var links: MarkdownLinks
    /// Colours fenced code by its language, or nil to draw code in the theme's code style.
    public var highlighter: (any MarkdownCodeHighlighter)?
    /// One walker for every block, so a walk allocates nothing for its stacks once they are as deep as the deepest block.
    private var walker: MarkdownEvents?

    /// A renderer of `theme`, `links` and `highlighter`.
    public init(
        theme: MarkdownTheme = .standard, links: MarkdownLinks = MarkdownLinks(),
        highlighter: (any MarkdownCodeHighlighter)? = nil
    ) {
        self.theme = theme
        self.links = links
        self.highlighter = highlighter
    }

    /// The rows of `block`, at most `width` columns wide.
    ///
    /// A row is wider only where a single grapheme is wider than the width (a wide character at a width of one).
    /// - Parameters:
    ///   - block: A top-level block of `document`.
    ///   - document: The document the block is in.
    ///   - width: The columns a row may take; less than one counts as one.
    /// - Returns: The block's rows, at least one.
    /// - Complexity: O(the block's source and rows).
    public mutating func lines(of block: MarkdownBlock, in document: MarkdownDocument, width: Int) -> [StyledLine] {
        var events: MarkdownEvents
        if let reused = walker {
            events = reused
            walker = nil
            events.restart(at: block, in: document)
        } else {
            events = document.events(of: block)
        }
        var writer = BlockWriter(theme: theme, links: links, highlighter: highlighter, width: width, document: document)
        while let event = events.next() { writer.handle(event) }
        walker = events
        return writer.lines.isEmpty ? [StyledLine()] : writer.lines
    }

    /// The rows of every block of `document`, a blank row between top-level blocks.
    ///
    /// - Parameters:
    ///   - document: The document.
    ///   - width: The columns a row may take; less than one counts as one.
    /// - Returns: The document's rows; none for an empty document.
    public mutating func lines(of document: MarkdownDocument, width: Int) -> [StyledLine] {
        var lines: [StyledLine] = []
        for block in document.topLevelBlocks {
            if !lines.isEmpty { lines.append(StyledLine()) }
            lines += self.lines(of: block, in: document, width: width)
        }
        return lines
    }
}
