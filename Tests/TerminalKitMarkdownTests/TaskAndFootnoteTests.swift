import AemiMarkdown
import Testing

@testable import TerminalKitMarkdown

/// A task item's text starts where every item's text starts, and the notes sit under a rule (the viewer's rules, ported).
@Suite("Task items and footnotes")
struct TaskAndFootnoteTests {
    private func rows(_ markdown: String, theme: MarkdownTheme = .standard, width: Int = 60) -> [String] {
        Rendered.rows(markdown, width: width, theme: theme)
    }

    @Test func `a task takes the place of the bullet with a checkbox drawn in strokes, the same width done or not`() {
        let out = rows("- plain\n- [x] done\n- [ ] open\n  - [ ] nested\n  - nested plain")
        #expect(out == ["• plain", "[✓] done", "[ ] open", "    [ ] nested", "    ◦ nested plain"])
    }

    @Test func `a wrapped task item hangs under its text`() {
        let out = rows("- [x] one two three four five six seven eight", width: 20)
        #expect(
            out.first?.hasPrefix("[✓] one") == true
                && out.dropFirst().allSatisfy { $0.hasPrefix("    ") && !$0.hasPrefix("     ") }
        )
    }

    @Test func `an ordered list keeps its number and the checkbox follows it`() {
        #expect(rows("1. [x] done\n2. [ ] open") == ["1. [x] done", "2. [ ] open"])
    }

    @Test func `a theme without glyphs keeps the bracketed form`() {
        #expect(rows("- [x] done\n- [ ] open", theme: .plain).count == 2)
    }

    @Test func `the notes of a document are under one rule`() {
        let out = rows("text[^a] more[^b]\n\n[^a]: one\n\n[^b]: two\n\nafter")
        #expect(out.filter { $0.hasPrefix("────") }.count == 1)
        let rule = out.firstIndex { $0.hasPrefix("────") }
        #expect(rule != nil && out[(rule ?? 0) + 1].hasPrefix("[^a]: one") && out.last == "after")
    }

    @Test func `a block is told whether it starts the notes`() {
        let document = Rendered.document("t[^a]\n\n[^a]: one\n\n[^b]: two\n\nlast")
        let renderer = MarkdownRenderer(theme: .standard)
        let starts = document.topLevelBlocks.map { renderer.startsFootnotes($0, in: document) }
        #expect(starts == [false, true, false, false])
        #expect(renderer.footnoteRule(width: 5)?.width == 5 && renderer.footnoteRule(width: 60)?.width == 8)
        #expect(MarkdownRenderer(theme: .plain).footnoteRule(width: 60) == nil)
    }
}
