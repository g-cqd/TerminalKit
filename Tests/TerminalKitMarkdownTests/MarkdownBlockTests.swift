import AemiMarkdown
import TerminalKitStyle
import TerminalKitText
import Testing

@testable import TerminalKitMarkdown

@Suite("Blocks become rows: prose wraps, containers prefix their rows, code keeps its lines")
struct MarkdownBlockTests {
    @Test(arguments: [1, 2, 7, 12, 20, 33, 80])
    func `a paragraph of plain words wraps as TextWrap wraps the same text`(width: Int) {
        let text = "The quick brown fox jumps over the lazy dog, and then a much longerwordthanmost runs past it again."
        #expect(Rendered.rows(text, width: width) == TextWrap.lines(text, width: width))
    }

    @Test func `blocks are a blank row apart, a soft break is a space and a hard break a new row`() {
        #expect(
            Rendered.rows("# Head\n\none\ntwo  \nthree\n\n---\n", width: 10) == [
                "Head", "", "one two", "three", "", "──────────"
            ])
    }

    @Test func `quotes put a bar before each row, nested quotes one per level, and an alert names itself`() {
        #expect(Rendered.rows("> a b c d e f\n>\n> > inner\n", width: 9) == ["│ a b c d", "│ e f", "│", "│ │ inner"])
        #expect(Rendered.rows("> [!WARNING]\n> careful\n") == ["│ Warning", "│ careful"])
    }

    @Test func `list items take a marker on their first row and its width on the others`() {
        #expect(
            Rendered.rows("- one two three\n- four\n  - five\n", width: 9) == [
                "• one two", "  three", "• four", "  ◦ five"
            ])
        #expect(Rendered.rows("7) seven\n8) eight\n") == ["7) seven", "8) eight"])
        #expect(Rendered.rows("1. a\n\n2. b\n") == ["1. a", "", "2. b"])
        #expect(Rendered.rows("- [x] done\n- [ ] open\n") == ["• [x] done", "• [ ] open"])
        #expect(Rendered.rows("-\n- b\n") == ["• ", "• b"])
    }

    @Test func `a code block shows its language, keeps its lines after a gutter, expands tabs and cuts at the width`() {
        let rows = Rendered.rows("```swift\nlet a\tb\n\nabcdefghij\n```\n", width: 8)
        #expect(rows == ["  swift", "  let a ", "    b", "  ", "  abcdef", "  ghij"])
    }

    /// Colours `let` and nothing else, and only Swift.
    private struct Keywords: MarkdownCodeHighlighter {
        func highlight(_ lines: [String], language: String) -> [[MarkdownHighlight]]? {
            guard language == "swift" else { return nil }
            return lines.map {
                $0.hasPrefix("let") ? [MarkdownHighlight(bytes: 0 ..< 3, style: Style(bold: true))] : []
            }
        }
    }

    @Test func `a highlighter colours the code of the languages it knows, over the code block style`() {
        var renderer = MarkdownRenderer(theme: .plain, highlighter: Keywords())
        let swift = renderer.lines(of: Rendered.document("```swift\nlet a\n```\n"), width: 20)
        #expect(swift[1].runs.map(\.text) == ["  ", "let", " a"])
        #expect(swift[1].runs[1].style == Style(bold: true))
        #expect(swift[1].runs[1].source == 9 ..< 12)
        let other = renderer.lines(of: Rendered.document("```py\nlet a\n```\n"), width: 20)
        #expect(other[1].runs.map(\.text) == ["  ", "let a"])
    }

    @Test func `an HTML block shows as written and a footnote takes its label as a marker`() {
        #expect(Rendered.rows("<div>\n*x*\n</div>\n") == ["<div>", "*x*", "</div>"])
        #expect(Rendered.rows("a[^n]\n\n[^n]: the note\n") == ["a[^n]", "", "[^n]: the note"])
    }

    @Test func `a nesting deeper than the width allows keeps half the row for the text`() {
        let rows = Rendered.lines("> > > > > deep words here\n", width: 8)
        for row in rows {
            #expect(row.width <= 8)
            #expect(row.runs.filter { $0.source != nil }.reduce(0) { $0 + UnicodeWidth.displayWidth(of: $1.text) } <= 4)
        }
        #expect(rows.map(\.text).joined(separator: " ").contains("deep"))
    }

    @Test func `streaming: a final block lays out as it does in the finished document`() {
        let markdown = "# Title\n\nA paragraph that\ngoes on.\n\n- a\n- b\n\n```\ncode\n```\n\nlast words"
        let bytes = Array(markdown.utf8)
        var parser = MarkdownParser()
        var renderer = MarkdownRenderer()
        var final: [Int: [StyledLine]] = [:]
        for start in stride(from: 0, to: bytes.count, by: 5) {
            parser.append(Array(bytes[start ..< Swift.min(start + 5, bytes.count)]))
            let snapshot = parser.snapshot()
            for block in snapshot.topLevelBlocks where block.isFinal && final[block.id] == nil {
                final[block.id] = renderer.lines(of: block, in: snapshot, width: 20)
            }
        }
        parser.finish()
        let document = parser.snapshot()
        var fresh = MarkdownRenderer()
        #expect(!final.isEmpty)
        for block in document.topLevelBlocks {
            if let kept = final[block.id] { #expect(kept == fresh.lines(of: block, in: document, width: 20)) }
        }
    }
}
