import AemiMarkdown
import TerminalKitText
import Testing

@testable import TerminalKitMarkdown

@Suite("Properties over a corpus and random documents, at every width from 1 to 100")
struct MarkdownPropertyTests {
    static let corpus = [
        "# Title *em* **strong** `code`\n\nA paragraph with [a link](https://example.com) and www.example.com.\n",
        "> quote\n> > nested with a long line of words to wrap\n>\n> - item\n>   1. sub\n",
        "- [x] task\n- [ ] open task with words\n  continued\n\n  second paragraph\n",
        "```swift\nlet a = 1\tlet b = \"日本語のテキスト\"\n\tindented\n```\n",
        "| a | b | c |\n|:-|:-:|-:|\n| 1 | two words | three more words here |\n| é | 日本 | x |\n",
        "Text with &amp; &#x1F600; &copy; and a\u{1B}[31m escape and\ttab.\n",
        "Footnote[^1] here.\n\n[^1]: The note with *em*.\n",
        "<div>\nraw html\n</div>\n\n---\n\n    indented code\n",
        "> [!TIP]\n> an alert with `code` and **bold**\n",
        "日本語の文章はスペースなしで長く続きますので折り返しが必要です。\n",
        "1. a\n2. b\n   - c\n     - d\n       - e\n         - f deep\n",
        "$x + y$ and $$\\sum$$ math\n",
        "line one\\\nline two  \nline three\n"
    ]

    static let fragments = [
        "# ", "## ", "> ", "- ", "1. ", "* ", "```\n", "```py\n", "| a | b |\n|---|---|\n", "| 1 | 2 |", "**", "*", "_",
        "`", "~~",
        "[x](https://a.example)", "[y](mailto:a@b.c)", "<https://z.example>", "&amp;", "&#9731;", "\t", "\u{1B}",
        "\u{7}", "日本",
        "é", "👍🏽", "www.x.com", "a@b.co", "[^1]", "[^1]: ", "<b>", "</b>", "    ", "\\", "  ", "\n", "\n\n", "---",
        "[!NOTE]",
        "- [ ] ", "word", "words", "longerwordthanmost", " ", " ", " ", "$x$", "<!-- c -->", "![alt](i.png)"
    ]

    static func randomDocuments() -> [String] {
        var random = SplitMix(state: 0x5EED)
        return (0 ..< 150)
            .map { _ in
                (0 ..< Int.random(in: 1 ... 60, using: &random))
                    .map { _ in fragments.randomElement(using: &random) ?? "" }.joined()
            }
    }

    /// Each printable ASCII byte that is not a space, in a leaf whose text the reader should see, is shown by some run.
    @Test(arguments: [SoftBreaks.space, .lineBreak])
    func `every printable byte of the source text is shown, in every row no wider than the width`(breaks: SoftBreaks) {
        for markdown in Self.corpus + Self.randomDocuments() {
            let document = Rendered.document(markdown)
            let expected = Self.visibleBytes(document)
            var renderer = MarkdownRenderer(softBreaks: breaks)
            for width in 1 ... 100 {
                let lines = renderer.lines(of: document, width: width)
                var shown = Set<Int>()
                for line in lines {
                    #expect(line.width <= Swift.max(width, 2), "\(width) \(markdown.debugDescription): \(line.text)")
                    for run in line.runs {
                        if let source = run.source { shown.formUnion(source) }
                    }
                }
                let missing = expected.subtracting(shown)
                #expect(missing.isEmpty, "\(width) \(markdown.debugDescription): missing \(missing.sorted().prefix(5))")
            }
        }
    }

    /// A run shows its source as written, or decoded, or as the spaces of a tab.
    @Test func `a run's text is its source bytes, their decoding, or spaces`() {
        for markdown in Self.corpus + Self.randomDocuments() {
            let document = Rendered.document(markdown)
            var renderer = MarkdownRenderer()
            for width in [1, 3, 10, 40, 100] {
                for run in renderer.lines(of: document, width: width).flatMap(\.runs) {
                    guard let source = run.source else { continue }
                    let written = String(
                        decoding: document.source[source].map { $0 == 0x09 ? 0x20 : $0 }, as: UTF8.self)
                    let decoded = String(decoding: document.decode(source), as: UTF8.self)
                    #expect(
                        run.text == written || run.text == decoded || run.text.allSatisfy { $0 == " " },
                        "\(markdown.debugDescription): \(run.text.debugDescription) for \(written.debugDescription)")
                    #expect(!run.text.unicodeScalars.contains(where: TextSanitizer.isControl))
                }
            }
        }
    }

    @Test func `a renderer reused across blocks and widths draws what a fresh one draws`() {
        var reused = MarkdownRenderer()
        for markdown in Self.corpus + Self.randomDocuments().prefix(40) {
            let document = Rendered.document(markdown)
            for width in [100, 7, 1, 33] {
                var fresh = MarkdownRenderer()
                #expect(reused.lines(of: document, width: width) == fresh.lines(of: document, width: width))
            }
        }
    }

    /// The source bytes of what a reader should see: text, raw HTML, code, footnote labels, entities.
    static func visibleBytes(_ document: MarkdownDocument) -> Set<Int> {
        var bytes = Set<Int>()
        for block in document.topLevelBlocks {
            var events = document.events(of: block)
            while let event = events.next() {
                guard case .leaf(let node) = event else { continue }
                switch node.kind {
                    case .text, .htmlInline, .codeLine, .footnoteReference, .footnoteLabel, .entity:
                        for index in node.range where document.source[index] > 0x20 && document.source[index] < 0x7F {
                            bytes.insert(index)
                        }
                    default: break
                }
            }
        }
        return bytes
    }
}
