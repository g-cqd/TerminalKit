public import TerminalKitStyle

/// How a rendered document looks: the style of each kind of text, and the glyphs of the chrome around it.
///
/// The styles named as overlays apply over the text they are in: an overlay sets what it names, a colour other than `.default` and each
/// attribute that is on, and leaves the rest. Colours are palette indices, so the terminal's own theme applies. Every glyph is one column in
/// each terminal measured (roadmap 0013), so a row's width is known.
public struct MarkdownTheme: Sendable, Equatable {
    /// Paragraphs, list items, cells.
    public var text: Style
    /// Headings by level, 1 first; a level past the end takes the last.
    public var headings: [Style]
    /// Overlays for `*emphasis*`, `**strong**` and `~~strikethrough~~`.
    public var emphasis: Style
    public var strong: Style
    public var strikethrough: Style
    /// Overlay for a code span and for math.
    public var code: Style
    /// A code block's lines, its language label, and its gutter.
    public var codeBlock: Style
    public var codeLabel: Style
    public var codeGutter: String
    /// Overlay for a link's text, and the style of a target shown after it.
    public var link: Style
    public var linkTarget: Style
    /// Raw HTML, inline and as a block, shown as written.
    public var html: Style
    /// List markers, task markers and footnote labels.
    public var marker: Style
    /// The bar before each line of a quote, and an alert's title.
    public var quote: Style
    public var quoteBar: String
    /// A thematic break, drawn across the width.
    public var rule: Style
    public var ruleGlyph: Character
    /// Bullets by list depth, outermost first, repeating.
    public var bullets: [String]
    /// A table's column separator, the rule under its header and where the two cross, and an overlay for header cells.
    public var tableBorder: Style
    public var tableColumnSeparator: String
    public var tableRuleGlyph: Character
    public var tableRuleJunction: String
    public var tableHeader: Style

    /// A theme of the given styles; every glyph has the ``standard`` theme's default.
    public init(
        text: Style = .default, headings: [Style] = [Style(bold: true)], emphasis: Style = Style(italic: true),
        strong: Style = Style(bold: true), strikethrough: Style = Style(strikethrough: true), code: Style = .default,
        codeBlock: Style = .default, codeLabel: Style = .default, link: Style = .default, linkTarget: Style = .default,
        html: Style = .default, marker: Style = .default, quote: Style = .default, rule: Style = .default,
        tableBorder: Style = .default, tableHeader: Style = Style(bold: true)
    ) {
        self.text = text
        self.headings = headings.isEmpty ? [.default] : headings
        self.emphasis = emphasis
        self.strong = strong
        self.strikethrough = strikethrough
        self.code = code
        self.codeBlock = codeBlock
        self.codeLabel = codeLabel
        codeGutter = "  "
        self.link = link
        self.linkTarget = linkTarget
        self.html = html
        self.marker = marker
        self.quote = quote
        quoteBar = "│ "
        self.rule = rule
        ruleGlyph = "─"
        bullets = ["•", "◦", "▪"]
        self.tableBorder = tableBorder
        tableColumnSeparator = " │ "
        tableRuleGlyph = "─"
        tableRuleJunction = "─┼─"
        self.tableHeader = tableHeader
    }

    /// Colour from the terminal's palette: cyan code, blue underlined links, magenta headings, dim chrome.
    public static let standard = MarkdownTheme(
        headings: [
            Style(fg: .indexed(5), bold: true, underline: .single), Style(fg: .indexed(5), bold: true),
            Style(fg: .indexed(5), bold: true, dim: false), Style(bold: true)
        ],
        code: Style(fg: .indexed(6)), codeBlock: .default, codeLabel: Style(dim: true, italic: true),
        link: Style(fg: .indexed(4), underline: .single), linkTarget: Style(dim: true), html: Style(dim: true),
        marker: Style(fg: .indexed(3)), quote: Style(dim: true), rule: Style(dim: true), tableBorder: Style(dim: true)
    )

    /// No colour: bold headings, strong and header cells, italic emphasis, struck strikethrough, and everything else in the default style.
    public static let plain = MarkdownTheme()

    /// The style of a heading of `level`.
    func heading(_ level: Int) -> Style { headings[Swift.min(Swift.max(level, 1), headings.count) - 1] }
}
