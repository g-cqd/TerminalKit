import Testing

@testable import TerminalKitText

/// Editable word wrapping keeps source characters, including whitespace, and uses one map for the drawn rows and their carets.
@Suite("Editable words wrap without changing their source")
struct WordInputLayoutTests {
    @Test func `a word moves whole to the next row and spaces stay in the source`() {
        let layout = InputLayout("hello world", columns: 8, wrapsWords: true)
        #expect(layout.rows == ["hello ", "world"])
        #expect(layout.position(at: 6) == .init(row: 1, column: 0))
        #expect(layout.offset(atRow: 0, column: 7) == 5)
        #expect(layout.offset(atRow: 1, column: 0) == 6)
        #expect(layout.position(at: 11) == .init(row: 1, column: 5))
    }

    @Test func `prefixes, long words, tabs and hard newlines keep their caret rules`() {
        let layout = InputLayout("hi there\nabcdefghijk\tx", columns: 8, firstRowIndent: 3, wrapsWords: true)
        #expect(layout.rows == ["hi ", "there", "abcdefgh", "ijk x"])
        #expect(layout.position(at: 3) == .init(row: 1, column: 0))
        #expect(layout.position(at: 9) == .init(row: 2, column: 0))
        #expect(layout.offset(atRow: 3, column: 4) == 21)
        #expect(InputLayout("abcd", columns: 4, wrapsWords: true).rows == ["abcd", ""])
    }

    @Test func `wide and combining graphemes wrap by display width`() {
        let layout = InputLayout("a 日本語 e\u{301}", columns: 6, wrapsWords: true)
        #expect(layout.rows == ["a ", "日本語", " e\u{301}"])
        #expect(layout.position(at: 2) == .init(row: 1, column: 0))
        #expect(layout.offset(atRow: 1, column: 3) == 3)
        #expect(layout.position(at: 7) == .init(row: 2, column: 2))
    }

    @Test func `every character boundary round trips at narrow and resized widths`() {
        for text in [
            "", "a b cd efgh", "日本語 e\u{301} x", "  a   b  ", "x\ty\n\nZ", "a\u{1B} b", "ab\r\ncd", "ab\u{200B} c",
            "abc \u{301}def"
        ] {
            for columns in 1 ... 16 {
                let layout = InputLayout(text, columns: columns, firstRowIndent: 3, wrapsWords: true)
                for offset in 0 ... text.count {
                    let position = layout.position(at: offset)
                    #expect(
                        layout.position(at: layout.offset(atRow: position.row, column: position.column)) == position
                    )
                    #expect(position.column < layout.columns)
                }
                #expect(layout.rows.allSatisfy { UnicodeWidth.displayWidth(of: $0) <= columns })
            }
        }
    }
}
