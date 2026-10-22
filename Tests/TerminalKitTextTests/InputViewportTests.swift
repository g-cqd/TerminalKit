import Testing

@testable import TerminalKitText

@Suite("A bounded input scrolls by display row and keeps its cursor visible")
struct InputViewportTests {
    @Test func `the window is capped at the number of rows the host asks for`() {
        let layout = InputLayout((1 ... 10).map { "line \($0)" }.joined(separator: "\n"), columns: 20)
        let view = InputViewport(layout: layout, cursorOffset: 70, maximumRows: 3)
        #expect(view.visibleRows == 7 ..< 10)
        #expect(view.rowsAbove == 7 && view.rowsBelow == 0)
        #expect(view.cursor.row == 2 && view.cursor.column == 7)
    }

    @Test func `a cursor already in the viewport does not move it`() {
        let layout = InputLayout("0\n1\n2\n3\n4\n5\n6\n7\n8\n9", columns: 10)
        let view = InputViewport(layout: layout, cursorOffset: 13, maximumRows: 3, firstRow: 5)
        #expect(view.visibleRows == 5 ..< 8)
        #expect(view.cursor.row == 1 && view.rowsBelow == 2)
    }

    @Test func `the viewport follows the cursor back up and clamps after a resize`() {
        let layout = InputLayout("0\n1\n2\n3\n4\n5\n6\n7\n8\n9", columns: 10)
        let above = InputViewport(layout: layout, cursorOffset: 4, maximumRows: 3, firstRow: 5)
        #expect(above.visibleRows == 2 ..< 5 && above.cursor.row == 0)
        let taller = InputViewport(layout: layout, cursorOffset: 19, maximumRows: 50, firstRow: 8)
        #expect(taller.visibleRows == 0 ..< 10 && taller.rowsAbove == 0 && taller.rowsBelow == 0)
    }

    @Test func `a row cap below one still gives the cursor one row`() {
        let layout = InputLayout("ab\ncd", columns: 2)
        let view = InputViewport(layout: layout, cursorOffset: 5, maximumRows: 0, firstRow: -10)
        #expect(view.visibleRows.count == 1)
        #expect(view.cursor.row == 0 && view.cursor.column == 0)
    }

    @Test func `wrapped rows and wide graphemes use the same viewport as hard lines`() {
        let layout = InputLayout("a日本e\u{301}x", columns: 4)
        let view = InputViewport(layout: layout, cursorOffset: 3, maximumRows: 1)
        #expect(view.visibleRows == 1 ..< 2)
        #expect(view.cursor == .init(row: 0, column: 2))
        #expect(view.rowsAbove == 1 && view.rowsBelow == 1)
    }

    @Test func `every cursor remains within every positive or clamped cap`() {
        for columns in 1 ... 12 {
            let text = "one 日本\n\nsecond e\u{301} line\nlast"
            let layout = InputLayout(text, columns: columns, firstRowIndent: 5)
            for offset in 0 ... text.count {
                for cap in 0 ... 5 {
                    let view = InputViewport(layout: layout, cursorOffset: offset, maximumRows: cap, firstRow: 50)
                    #expect((1 ... max(1, cap)).contains(view.visibleRows.count))
                    #expect(view.visibleRows.contains(layout.position(at: offset).row))
                    #expect((0 ..< view.visibleRows.count).contains(view.cursor.row))
                    #expect(view.rowsAbove + view.visibleRows.count + view.rowsBelow == layout.rows.count)
                }
            }
        }
    }
}
