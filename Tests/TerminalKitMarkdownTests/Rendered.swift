import AemiMarkdown
import TerminalKitMarkdown

/// A document rendered for a test: its rows as text, or as styled lines.
enum Rendered {
    static func document(_ markdown: String) -> MarkdownDocument { MarkdownParser.parse(Array(markdown.utf8)) }

    static func lines(
        _ markdown: String, width: Int = 80, theme: MarkdownTheme = .plain, links: MarkdownLinks = MarkdownLinks(),
        softBreaks: SoftBreaks = .space
    ) -> [StyledLine] {
        var renderer = MarkdownRenderer(theme: theme, links: links, softBreaks: softBreaks)
        return renderer.lines(of: document(markdown), width: width)
    }

    static func rows(
        _ markdown: String, width: Int = 80, theme: MarkdownTheme = .plain, links: MarkdownLinks = MarkdownLinks()
    ) -> [String] {
        lines(markdown, width: width, theme: theme, links: links).map(\.text)
    }

    /// The run that shows `text`, in the rendering of `markdown`.
    static func run(
        _ text: String, in markdown: String, theme: MarkdownTheme = .plain, links: MarkdownLinks = MarkdownLinks()
    )
        -> StyledRun?
    {
        lines(markdown, theme: theme, links: links).flatMap(\.runs).first { $0.text == text }
    }
}

/// A seeded generator, so a failing random case can be run again.
struct SplitMix: RandomNumberGenerator {
    var state: UInt64

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var value = state
        value = (value ^ (value >> 30)) &* 0xBF58_476D_1CE4_E5B9
        value = (value ^ (value >> 27)) &* 0x94D0_49BB_1331_11EB
        return value ^ (value >> 31)
    }
}
