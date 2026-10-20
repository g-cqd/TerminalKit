import Testing

@testable import TerminalKitText

@Suite("A drag and a click make a selection")
struct SelectionControllerTests {
    /// Rows of "alpha one" ... as drawn by the stand-in layout at 20 columns; row 0 is "alpha one".
    private let map = rowMap(for: sample, width: 20, scroll: 0, rows: 12)

    private func text(_ controller: SelectionController<String>) -> String? {
        controller.selection?.text(in: sample)
    }

    @Test func `a drag selects from the grapheme under the press to the one under the pointer, both included`() {
        var controller = SelectionController<String>()
        _ = controller.beginDrag(row: 0, col: 1, rows: map)
        let update = controller.drag(row: 0, col: 4, rows: map, scrollableRows: 0 ..< 12)
        #expect(update.changed)
        #expect(text(controller) == "lpha")
    }

    @Test func `a drag backwards selects the same graphemes at its two ends`() {
        var controller = SelectionController<String>()
        _ = controller.beginDrag(row: 0, col: 4, rows: map)
        _ = controller.drag(row: 0, col: 1, rows: map, scrollableRows: 0 ..< 12)
        #expect(text(controller) == "lpha")
    }

    @Test func `a drag across blocks reads them in order, joined by a line feed`() {
        var controller = SelectionController<String>()
        _ = controller.beginDrag(row: 1, col: 6, rows: map)
        _ = controller.drag(row: 3, col: 1, rows: map, scrollableRows: 0 ..< 12)
        #expect(text(controller) == "two\nbe")
    }

    @Test func `a press and release that never moved selects nothing and does not ask to copy`() {
        var controller = SelectionController<String>()
        _ = controller.beginDrag(row: 0, col: 3, rows: map)
        let update = controller.endDrag()
        #expect(controller.selection == nil)
        #expect(!update.committed)
    }

    @Test func `motion inside the pressed cell is a wobbling click, not a one-grapheme selection`() {
        var controller = SelectionController<String>()
        _ = controller.beginDrag(row: 0, col: 3, rows: map)
        let update = controller.drag(row: 0, col: 3, rows: map, scrollableRows: 0 ..< 12)
        #expect(!update.changed)
        #expect(controller.selection == nil)
        #expect(!controller.endDrag().committed)
    }

    @Test func `releasing a real drag commits the selection once`() {
        var controller = SelectionController<String>()
        _ = controller.beginDrag(row: 0, col: 0, rows: map)
        _ = controller.drag(row: 0, col: 4, rows: map, scrollableRows: 0 ..< 12)
        #expect(controller.endDrag().committed)
        #expect(!controller.endDrag().committed)
        #expect(!controller.isDragging)
    }

    @Test func `a drag that reaches the first or last scrolling row asks for a scroll`() {
        var controller = SelectionController<String>()
        _ = controller.beginDrag(row: 4, col: 0, rows: map)
        #expect(controller.drag(row: 2, col: 2, rows: map, scrollableRows: 2 ..< 8).scroll == .up)
        #expect(controller.drag(row: 7, col: 2, rows: map, scrollableRows: 2 ..< 8).scroll == .down)
        #expect(controller.drag(row: 5, col: 2, rows: map, scrollableRows: 2 ..< 8).scroll == nil)
    }

    @Test func `the selection stays anchored in the content while the rows move under the pointer`() {
        var controller = SelectionController<String>()
        _ = controller.beginDrag(row: 0, col: 0, rows: map)
        _ = controller.drag(row: 0, col: 4, rows: map, scrollableRows: 0 ..< 12)
        // The host scrolled two rows: row 0 is now the blank row between blocks and "beta" is on row 1, under the pointer.
        let scrolled = rowMap(for: sample, width: 20, scroll: 2, rows: 12)
        _ = controller.drag(row: 1, col: 3, rows: scrolled, scrollableRows: 0 ..< 12)
        #expect(text(controller) == "alpha one\nalpha two\nbeta")
    }

    @Test func `a double click selects the word and a triple click the line, each ready to copy`() {
        var controller = SelectionController<String>()
        let word = controller.click(row: 0, col: 7, count: 2, rows: map, content: sample)
        #expect(word.committed)
        #expect(text(controller) == "one")
        let line = controller.click(row: 1, col: 7, count: 3, rows: map, content: sample)
        #expect(line.committed)
        #expect(text(controller) == "alpha two")
    }

    @Test func `a single click clears a selection and reports the change`() {
        var controller = SelectionController<String>()
        _ = controller.click(row: 0, col: 7, count: 2, rows: map, content: sample)
        let update = controller.click(row: 0, col: 7, count: 1, rows: map, content: sample)
        #expect(update.changed)
        #expect(!update.committed)
        #expect(controller.selection == nil)
        #expect(!controller.click(row: 0, col: 7, count: 1, rows: map, content: sample).changed)
    }

    @Test func `a press over padding snaps to the nearest content and a drag from it still works`() {
        var controller = SelectionController<String>()
        // Row 2 is "beta" at row 2; the blank row 4 holds no content and snaps to the start of "gamma one" at row 5.
        _ = controller.beginDrag(row: 4, col: 0, rows: map)
        _ = controller.drag(row: 5, col: 4, rows: map, scrollableRows: 0 ..< 12)
        #expect(text(controller) == "gamma")
    }

    @Test func `a wide grapheme is selected whole when the pointer is on either of its cells`() {
        let wide = TestContent(blocks: [(id: "w", lines: ["a日本b"])])
        let map = rowMap(for: wide, width: 20, scroll: 0, rows: 4)
        for col in [1, 2] {
            var controller = SelectionController<String>()
            _ = controller.beginDrag(row: 0, col: 0, rows: map)
            _ = controller.drag(row: 0, col: col, rows: map, scrollableRows: 0 ..< 4)
            #expect(controller.selection?.text(in: wide) == "a日", "col \(col)")
        }
    }

    @Test func `clear forgets the selection and the drag`() {
        var controller = SelectionController<String>()
        _ = controller.beginDrag(row: 0, col: 0, rows: map)
        _ = controller.drag(row: 0, col: 4, rows: map, scrollableRows: 0 ..< 12)
        controller.clear()
        #expect(controller.selection == nil)
        #expect(!controller.isDragging)
        #expect(!controller.drag(row: 0, col: 6, rows: map, scrollableRows: 0 ..< 12).changed)
    }
}

@Suite("A highlight splits a row at its columns")
struct ColumnSlicerTests {
    @Test func `the text is split before, inside and after the columns`() {
        let parts = ColumnSlicer.split("alpha one", columns: 2 ..< 5)
        #expect((parts.before, parts.selected, parts.after) == ("al", "pha", " one"))
    }

    @Test func `wide graphemes are never cut in half`() {
        let parts = ColumnSlicer.split("a日本b", columns: 1 ..< 3)
        #expect((parts.before, parts.selected, parts.after) == ("a", "日", "本b"))
    }

    @Test func `columns past the end select to the end and an empty range selects nothing`() {
        let end = ColumnSlicer.split("abc", columns: 1 ..< 99)
        #expect((end.before, end.selected, end.after) == ("a", "bc", ""))
        let none = ColumnSlicer.split("abc", columns: 2 ..< 2)
        #expect((none.before, none.selected, none.after) == ("ab", "", "c"))
    }

    @Test func `the three parts always rebuild the text`() {
        for text in ["", "abc", "日本語", "e\u{301}x", "a\tb", "👨‍👩‍👧x"] {
            for low in 0 ... 6 {
                for high in low ... 7 {
                    let parts = ColumnSlicer.split(text, columns: low ..< high)
                    #expect(
                        parts.before + parts.selected + parts.after == text, "\(text.debugDescription) \(low)..<\(high)"
                    )
                }
            }
        }
    }
}
