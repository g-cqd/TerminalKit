import Testing

@testable import TerminalKitText

/// `TextWrap.rows` must be `TextWrap.lines` with provenance: the same texts, and for each one the hard line and grapheme offset a
/// selection needs to map a place on the screen back to the text (roadmap 0017).
@Suite("Wrapped rows say where they came from")
struct TextWrapRowsTests {
    private static let widths = [1, 2, 3, 4, 5, 7, 10, 20, 80]

    /// The hard lines of `text` as wrapped: tabs are four spaces, line feeds end lines.
    private static func hardLines(_ text: String) -> [[Character]] {
        text.replacing("\t", with: "    ").split(separator: "\n", omittingEmptySubsequences: false).map { Array($0) }
    }

    /// Everything a selection relies on, checked for one text and width.
    private static func check(_ text: String, width: Int) -> String? {
        let rows = TextWrap.rows(text, width: width)
        let lines = TextWrap.lines(text, width: width)
        guard rows.map(\.text) == lines else { return "texts differ from lines()" }
        let source = hardLines(text)
        guard rows.last?.line == source.count - 1 else {
            return "last row is line \(String(describing: rows.last?.line)), not \(source.count - 1)"
        }
        var previous: TextWrap.Row?
        for row in rows {
            guard source.indices.contains(row.line) else { return "row names line \(row.line) of \(source.count)" }
            let characters = source[row.line]
            let count = row.text.count
            guard row.offset >= 0, row.offset + count <= characters.count else {
                return "row \(row) runs past its line"
            }
            guard String(characters[row.offset ..< row.offset + count]) == row.text else {
                return "row \(row.text.debugDescription) is not the run at offset \(row.offset)"
            }
            if let before = previous {
                if before.line == row.line {
                    guard row.offset >= before.offset + before.text.count else {
                        return "row \(row) overlaps the one before"
                    }
                } else {
                    guard row.line == before.line + 1, row.offset == 0 else { return "row \(row) skips a hard line" }
                }
            } else {
                guard row.line == 0, row.offset == 0 else { return "first row is not at the start" }
            }
            previous = row
        }
        return nil
    }

    @Test func `a line that wraps at spaces drops each space and the next row starts one past it`() {
        #expect(
            TextWrap.rows("hello world foo", width: 8) == [
                TextWrap.Row(text: "hello", line: 0, offset: 0), TextWrap.Row(text: "world", line: 0, offset: 6),
                TextWrap.Row(text: "foo", line: 0, offset: 12)
            ])
    }

    @Test func `a word too long for a row is cut inside, with no space between the rows`() {
        #expect(
            TextWrap.rows("abcdefghij", width: 4) == [
                TextWrap.Row(text: "abcd", line: 0, offset: 0), TextWrap.Row(text: "efgh", line: 0, offset: 4),
                TextWrap.Row(text: "ij", line: 0, offset: 8)
            ])
    }

    @Test func `line feeds end hard lines, and an empty line is still a row`() {
        #expect(
            TextWrap.rows("ab\n\ncd ef", width: 2) == [
                TextWrap.Row(text: "ab", line: 0, offset: 0), TextWrap.Row(text: "", line: 1, offset: 0),
                TextWrap.Row(text: "cd", line: 2, offset: 0), TextWrap.Row(text: "ef", line: 2, offset: 3)
            ])
    }

    @Test func `offsets count graphemes, not bytes or scalars, so a wide character or an accent is one`() {
        // 日本語 fills six columns, so the space after it is the break; the rest (1 + 1 + 2 + 1 + 1 columns) fits one row.
        let rows = TextWrap.rows("日本語 e\u{301}x🇫🇷 y", width: 6)
        #expect(rows.map(\.text) == ["日本語", "e\u{301}x🇫🇷 y"])
        #expect(rows.map(\.offset) == [0, 4])
    }

    @Test func `tabs are four spaces, and offsets count the text as wrapped`() {
        let rows = TextWrap.rows("a\tb", width: 80)
        #expect(rows == [TextWrap.Row(text: "a    b", line: 0, offset: 0)])
        // "a    b cd": the row fills with the tab's spaces, breaks at the last of them, and "b cd" starts at grapheme 5.
        #expect(TextWrap.rows("a\tb cd", width: 5).map(\.offset) == [0, 5])
    }

    @Test func `a line exactly full at a space breaks at that space, and the next row starts after it`() {
        #expect(TextWrap.rows("abcd efgh", width: 4).map(\.offset) == [0, 5])
    }

    @Test(arguments: [
        "", " ", "  ", "a", "the quick brown fox jumps over the lazy dog", " leading and trailing ", "a\n\nb\n", "\n",
        "\n\n",
        "tab\tseparated\tvalues", "日本語のテキスト", "ab 日本 cd", "e\u{301}e\u{301} e\u{301}", "👨‍👩‍👧 family and ❤️ heart",
        "cr\r\nlf and\rbare",
        "x\r\n", "\r\n\r\n", "nul\u{0}inside", "👍🏽 ok", "flag 🇫🇷🇩🇪 pair", "a\u{200B}b", "\u{301}orphan mark", "\n日本",
        "end\n日",
        "a\n\u{301}", String(repeating: "word ", count: 50), String(repeating: "x", count: 300)
    ])
    func `a hand-picked text has rows that are the runs they say`(text: String) {
        for width in Self.widths {
            let problem = Self.check(text, width: width)
            #expect(problem == nil, "width \(width), text \(text.debugDescription): \(problem ?? "")")
        }
    }

    @Test func `generated texts have rows that are the runs they say`() {
        let pieces: [String] = [
            "a", "b", "word", " ", " ", " ", "\n", "\t", "\r", "\r\n", "日", "本", "é", "e\u{301}", "\u{301}", "👨‍👩‍👧", "❤️",
            "1️⃣", "🇫🇷", "🇫",
            "👍🏽", "\u{0}", "\u{200B}", "—", "✓", "ï", "ab cd ef"
        ]
        var state: UInt64 = 0x2545_F491_4F6C_DD1D
        func random(_ bound: Int) -> Int {
            state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            return Int(state >> 33) % bound
        }
        for _ in 0 ..< 3_000 {
            var text = ""
            for _ in 0 ..< random(40) { text += pieces[random(pieces.count)] }
            let width = Self.widths[random(Self.widths.count)]
            if let problem = Self.check(text, width: width) {
                Issue.record("width \(width), text \(text.debugDescription): \(problem)")
                return
            }
        }
    }
}
