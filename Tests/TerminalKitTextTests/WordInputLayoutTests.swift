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

    /// Found reviewing ask's input (2026-11-11): a word that ended in the last cell sent the space after it to the start of the next
    /// row (`hello world` / ` foo`), and typing that space moved the cursor down a row.
    @Test func `a word keeps a cell for the space after it, so no row starts with that space`() {
        #expect(InputLayout("hello world foo", columns: 11, wrapsWords: true).rows == ["hello ", "world foo"])
        // The same rows before and after the space is typed: the word does not jump when it is.
        #expect(InputLayout("hello world", columns: 11, wrapsWords: true).rows == ["hello ", "world"])
        #expect(InputLayout("hello world ", columns: 11, wrapsWords: true).rows == ["hello ", "world "])
        // The first word after a prefix is not moved, since the prefix would be left alone on its row: its space starts the next row.
        #expect(InputLayout("abc de", columns: 6, firstRowIndent: 3, wrapsWords: true).rows == ["abc", " de"])
        // A word as wide as the row has no cell to keep: it fills the row, as before.
        #expect(InputLayout("aaaa bbbb", columns: 4, wrapsWords: true).rows == ["aaaa", " ", "bbbb", ""])
    }

    @Test func `words shorter than the row, one space apart, never leave a row starting with a space`() {
        var seed: UInt64 = 11
        func random(_ n: Int) -> Int {
            seed = seed &* 6_364_136_223_846_793_005 &+ 1
            return Int(seed >> 33) % n
        }
        for _ in 0 ..< 300 {
            let columns = 6 + random(30)
            let words = (0 ..< 1 + random(30)).map { _ in String(repeating: "w", count: 1 + random(columns - 2)) }
            let layout = InputLayout(
                words.joined(separator: " "),
                columns: columns,

                wrapsWords: true
            )
            #expect(layout.rows.dropFirst().allSatisfy { !$0.hasPrefix(" ") }, "\(columns): \(layout.rows)")
            #expect(layout.rows.joined() == words.joined(separator: " "))
        }
    }
}
