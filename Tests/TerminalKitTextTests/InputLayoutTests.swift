import Testing

@testable import TerminalKitText

@Suite("An input maps source graphemes to wrapped display rows")
struct InputLayoutTests {
    @Test func `empty text has a caret after the reserved prefix`() {
        let layout = InputLayout("", columns: 20, firstRowIndent: 5)
        #expect(layout.rows == [""])
        #expect(layout.position(at: 0) == .init(row: 0, column: 5))
    }

    @Test func `a source boundary at a soft wrap belongs to the next row`() {
        let layout = InputLayout("abcdefghij", columns: 8, firstRowIndent: 5)
        #expect(layout.rows == ["abc", "defghij"])
        #expect(layout.position(at: 2) == .init(row: 0, column: 7))
        #expect(layout.position(at: 3) == .init(row: 1, column: 0))
        #expect(layout.position(at: 10) == .init(row: 1, column: 7))
        #expect(layout.offset(atRow: 0, column: 99) == 2)
        #expect(layout.offset(atRow: 1, column: 2) == 5)
    }

    @Test func `an exactly full input has an empty cursor row at its end`() {
        let layout = InputLayout("abcd", columns: 4)
        #expect(layout.rows == ["abcd", ""])
        #expect(layout.position(at: 4) == .init(row: 1, column: 0))
    }

    @Test func `a full line followed by a newline does not invent another blank row`() {
        let layout = InputLayout("abcd\nx", columns: 4)
        #expect(layout.rows == ["abcd", "x"])
        #expect(layout.position(at: 4) == .init(row: 1, column: 0))
        #expect(layout.position(at: 5) == .init(row: 1, column: 0))
        #expect(layout.position(at: 6) == .init(row: 1, column: 1))
    }

    @Test func `a newline after a full wide row cannot put the caret on a continuation cell`() {
        let layout = InputLayout("ab日\nx", columns: 4)
        #expect(layout.rows == ["ab日", "x"])
        #expect(layout.position(at: 3) == .init(row: 1, column: 0))
        #expect(layout.position(at: 4) == .init(row: 1, column: 0))
        #expect(layout.offset(atRow: 0, column: 3) == 2)
    }

    @Test func `hard newlines and empty lines keep their source offsets`() {
        let layout = InputLayout("ab\n\ncd", columns: 8, firstRowIndent: 2)
        #expect(layout.rows == ["ab", "", "cd"])
        #expect(layout.position(at: 2) == .init(row: 0, column: 4))
        #expect(layout.position(at: 3) == .init(row: 1, column: 0))
        #expect(layout.position(at: 4) == .init(row: 2, column: 0))
        #expect(layout.offset(atRow: 2, column: 1) == 5)
    }

    @Test func `wide characters move whole and combining clusters remain one offset`() {
        let layout = InputLayout("a日本e\u{301}x", columns: 4)
        #expect(layout.rows == ["a日", "本e\u{301}x", ""])
        #expect(layout.position(at: 2) == .init(row: 1, column: 0))
        #expect(layout.position(at: 3) == .init(row: 1, column: 2))
        #expect(layout.offset(atRow: 0, column: 2) == 1)
        #expect(layout.offset(atRow: 1, column: 1) == 2)
    }

    @Test func `tabs use display tab stops and remain one source offset`() {
        let layout = InputLayout("a\tb", columns: 12, firstRowIndent: 2)
        #expect(layout.rows == ["a b"])
        #expect(layout.position(at: 2) == .init(row: 0, column: 4))
        #expect(layout.offset(atRow: 0, column: 3) == 1)
    }

    @Test func `narrow and invalid sizes still give every cursor a cell`() {
        let layout = InputLayout("日x", columns: 0, firstRowIndent: 99)
        #expect(layout.columns == 1 && layout.firstRowIndent == 0)
        #expect(layout.rows == ["?", "x", ""])
        for offset in -1 ... 4 { #expect(layout.position(at: offset).column == 0) }
        #expect(layout.position(at: -1) == .init(row: 0, column: 0))
        #expect(layout.position(at: 99) == .init(row: 2, column: 0))
    }

    @Test func `controls are displayed as replacement text and cannot enter a terminal command`() {
        let layout = InputLayout("a\u{1B}b", columns: 8)
        #expect(layout.rows == ["a�b"])
        #expect(layout.position(at: 2) == .init(row: 0, column: 2))
    }

    @Test func `every generated caret stays inside the layout and maps back to the same cell`() {
        let pieces = ["a", " ", "日", "e\u{301}", "👨‍👩‍👧", "\n", "\t", "\u{200B}"]
        var seed: UInt64 = 47
        func random(_ n: Int) -> Int {
            seed = seed &* 6_364_136_223_846_793_005 &+ 1
            return Int(seed >> 33) % n
        }
        for _ in 0 ..< 400 {
            var text = ""
            for _ in 0 ..< random(80) { text += pieces[random(pieces.count)] }
            let layout = InputLayout(text, columns: 1 + random(30), firstRowIndent: random(8))
            let continuationCells = layout.rows.enumerated()
                .map { row, text in
                    var column = row == 0 ? layout.firstRowIndent : 0
                    var cells = Set<Int>()
                    for character in text {
                        let width = UnicodeWidth.displayWidth(of: character)
                        if width == 2 { cells.insert(column + 1) }
                        column += width
                    }
                    return cells
                }
            var before = InputLayout.Position(row: 0, column: 0)
            for offset in 0 ... text.count {
                let position = layout.position(at: offset)
                #expect(layout.rows.indices.contains(position.row))
                #expect((0 ..< layout.columns).contains(position.column))
                if continuationCells.indices.contains(position.row) {
                    #expect(!continuationCells[position.row].contains(position.column))
                }
                #expect((position.row, position.column) >= (before.row, before.column))
                let mapped = layout.offset(atRow: position.row, column: position.column)
                #expect(layout.position(at: mapped) == position)
                before = position
            }
        }
    }
}
