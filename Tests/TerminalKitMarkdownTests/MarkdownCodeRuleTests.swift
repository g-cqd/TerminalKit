import TerminalKitStyle
import Testing

@testable import TerminalKitMarkdown

/// A code block set off by a rule, when a theme asks for one: the language on a corner, a rule down the gutter, a closing corner. The
/// rule is chrome: no run of it carries source, so a selection copies the code alone.
@Suite("A theme may draw a code block inside a rule")
struct MarkdownCodeRuleTests {
    private var ruled: MarkdownTheme {
        var theme = MarkdownTheme.plain
        theme.codeGutter = "│ "
        theme.codeOpen = "╭─ "
        theme.codeClose = "╰─"
        theme.codeRule = Style(dim: true)
        return theme
    }

    @Test func `the language sits on the opening corner, the lines after the rule, and a corner closes it`() {
        let rows = Rendered.rows("before\n\n```swift\nlet a = 1\n\nprint(a)\n```\n\nafter", theme: ruled)
        #expect(rows == ["before", "", "╭─ swift", "│ let a = 1", "│ ", "│ print(a)", "╰─", "", "after"])
    }

    @Test func `a block with no language opens on the corner alone`() {
        #expect(Rendered.rows("```\nx\n```", theme: ruled) == ["╭─", "│ x", "╰─"])
    }

    @Test func `the rule is dim and carries no source, so only the code is copied`() {
        let lines = Rendered.lines("```swift\nlet a = 1\n```", theme: ruled)
        for line in lines {
            let chrome = line.runs.filter { ["╭─ ", "│ ", "╰─"].contains($0.text) }
            #expect(chrome.allSatisfy { $0.source == nil && $0.style.dim })
        }
        #expect(lines.flatMap(\.runs).filter { $0.source != nil }.map(\.text).joined() == "let a = 1")
    }

    @Test func `without the theme's rule a block is drawn as before`() {
        #expect(Rendered.rows("```swift\nx\n```", theme: .plain) == ["  swift", "  x"])
    }
}
