import Testing

@testable import TerminalKitText

/// Content for the tests: blocks of lines, each block named by a string.
private struct TestContent: SelectableContent {
    var blocks: [(id: String, lines: [String])]

    var blockCount: Int { blocks.count }
    func ordinal(of block: String) -> Int? { blocks.firstIndex { $0.id == block } }
    func blockID(at ordinal: Int) -> String { blocks[ordinal].id }
    func lineCount(ofBlockAt ordinal: Int) -> Int { blocks[ordinal].lines.count }
    func line(_ line: Int, ofBlockAt ordinal: Int) -> String { blocks[ordinal].lines[line] }
}

private typealias Position = ContentPosition<String>
private typealias Selection = ContentSelection<String>

private func at(_ block: String, _ line: Int, _ offset: Int) -> Position {
    Position(block: block, line: line, offset: offset)
}

private let sample = TestContent(blocks: [
    (id: "a", lines: ["alpha one", "alpha two"]),
    (id: "b", lines: ["beta"]),
    (id: "c", lines: ["gamma one", "", "gamma three"])
])

/// Draws content as rows of at most `width` cells, wrapping by grapheme, with one blank (content-free) row between blocks, then
/// shows `rows` rows from row `scroll`. It is a stand-in for a host's layout, and it records what each row shows.
private func rowMap(for content: TestContent, width: Int, scroll: Int, rows: Int, indent: Int = 0) -> RowMap<String> {
    var all: [RowProvenance<String>?] = []
    for (ordinal, block) in content.blocks.enumerated() {
        for (line, text) in block.lines.enumerated() {
            let characters = Array(text)
            if characters.isEmpty {
                all.append(
                    RowProvenance(block: block.id, ordinal: ordinal, line: line, firstOffset: 0, col: indent, text: ""))
            }
            var start = 0
            while start < characters.count {
                var end = start
                var used = 0
                while end < characters.count, used + UnicodeWidth.displayWidth(of: characters[end]) <= width {
                    used += UnicodeWidth.displayWidth(of: characters[end])
                    end += 1
                }
                if end == start { end += 1 }
                all.append(
                    RowProvenance(
                        block: block.id, ordinal: ordinal, line: line, firstOffset: start, col: indent,
                        text: String(characters[start ..< end])))
                start = end
            }
        }
        all.append(nil)
    }
    var map = RowMap<String>()
    map.reset(rowCount: rows)
    for row in 0 ..< rows where scroll + row < all.count {
        if let entry = all[scroll + row] { map.set(row: row, to: entry) }
    }
    return map
}

@Suite("A selection reads back as content")
struct ContentSelectionTextTests {
    @Test func `within one line`() {
        #expect(Selection(anchor: at("a", 0, 6), head: at("a", 0, 9)).text(in: sample) == "one")
    }

    @Test func `across lines of a block`() {
        #expect(Selection(anchor: at("a", 0, 6), head: at("a", 1, 5)).text(in: sample) == "one\nalpha")
    }

    @Test func `across blocks, joined by the block separator`() {
        let selection = Selection(anchor: at("a", 1, 6), head: at("c", 0, 5))
        #expect(selection.text(in: sample) == "two\nbeta\ngamma")
        #expect(selection.text(in: sample, blockSeparator: "\n\n") == "two\n\nbeta\n\ngamma")
    }

    @Test func `a selection made backwards reads the same as forwards`() {
        let forward = Selection(anchor: at("a", 0, 2), head: at("b", 0, 3))
        let backward = Selection(anchor: at("b", 0, 3), head: at("a", 0, 2))
        #expect(forward.text(in: sample) == backward.text(in: sample))
        #expect(forward.text(in: sample) == "pha one\nalpha two\nbet")
    }

    @Test func `an empty line inside a selection is kept`() {
        #expect(Selection(anchor: at("c", 0, 6), head: at("c", 2, 5)).text(in: sample) == "one\n\ngamma")
    }

    @Test func `offsets count graphemes, so an accent or an emoji is one`() {
        let content = TestContent(blocks: [(id: "x", lines: ["e\u{301}x🇫🇷y"])])
        #expect(Selection(anchor: at("x", 0, 0), head: at("x", 0, 1)).text(in: content) == "e\u{301}")
        #expect(Selection(anchor: at("x", 0, 2), head: at("x", 0, 3)).text(in: content) == "🇫🇷")
    }

    @Test func `positions past the end are clamped, because the content may have changed`() {
        #expect(Selection(anchor: at("b", 0, 2), head: at("b", 0, 99)).text(in: sample) == "ta")
        #expect(Selection(anchor: at("b", 7, 0), head: at("b", 9, 0)).text(in: sample) == "beta")
    }

    @Test func `a collapsed selection is empty, and one whose block is gone reads as nothing`() {
        #expect(Selection(at: at("a", 0, 3)).isCollapsed)
        #expect(Selection(at: at("a", 0, 3)).text(in: sample) == "")
        #expect(Selection(anchor: at("a", 0, 0), head: at("gone", 0, 1)).text(in: sample) == nil)
    }

    @Test func `a block added above does not move a selection, because it names its block`() {
        let selection = Selection(anchor: at("b", 0, 0), head: at("b", 0, 4))
        var grown = sample
        grown.blocks.insert((id: "new", lines: ["inserted above"]), at: 0)
        #expect(selection.text(in: sample) == "beta" && selection.text(in: grown) == "beta")
    }
}

@Suite("A cell maps back to a place in the content")
struct RowMapPositionTests {
    @Test func `a column on plain text names the grapheme under it, before it or after it`() {
        let map = rowMap(for: sample, width: 20, scroll: 0, rows: 10, indent: 2)
        #expect(map.position(row: 0, col: 2)?.position == at("a", 0, 0))
        #expect(map.position(row: 0, col: 5)?.position == at("a", 0, 3))
        #expect(map.position(row: 0, col: 5, edge: .trailing)?.position == at("a", 0, 4))
    }

    @Test func `left of the text is the start of the row and past its end is the end`() {
        let map = rowMap(for: sample, width: 20, scroll: 0, rows: 10, indent: 2)
        #expect(map.position(row: 0, col: 0)?.position == at("a", 0, 0))
        #expect(map.position(row: 0, col: 60)?.position == at("a", 0, 9))
        #expect(map.position(row: 0, col: 60, edge: .trailing)?.position == at("a", 0, 9))
    }

    @Test func `wide characters take two cells, so either cell of one lands on it`() {
        let content = TestContent(blocks: [(id: "w", lines: ["日本語abc"])])
        let map = rowMap(for: content, width: 40, scroll: 0, rows: 3, indent: 2)
        // columns: 日 2-3, 本 4-5, 語 6-7, a 8, b 9, c 10
        #expect(map.position(row: 0, col: 4)?.position == at("w", 0, 1))
        #expect(map.position(row: 0, col: 5)?.position == at("w", 0, 1))
        #expect(map.position(row: 0, col: 5, edge: .trailing)?.position == at("w", 0, 2))
        #expect(map.position(row: 0, col: 8)?.position == at("w", 0, 3))
    }

    @Test func `a tab spans cells to the next stop`() {
        let content = TestContent(blocks: [(id: "t", lines: ["a\tb"])])
        let map = rowMap(for: content, width: 40, scroll: 0, rows: 3)
        #expect(map.position(row: 0, col: 2)?.position == at("t", 0, 1))
        #expect(map.position(row: 0, col: 4)?.position == at("t", 0, 2))
    }

    @Test func `a wrapped line keeps its line, and each row adds its first offset`() {
        let content = TestContent(blocks: [(id: "w", lines: ["abcdefghij"])])
        let map = rowMap(for: content, width: 4, scroll: 0, rows: 4)
        #expect(map.position(row: 0, col: 1)?.position == at("w", 0, 1))
        #expect(map.position(row: 1, col: 1)?.position == at("w", 0, 5))
        #expect(map.position(row: 2, col: 1)?.position == at("w", 0, 9))
    }

    @Test func `a row with no content holds no position, and a drag snaps to the nearest row that has some`() {
        let map = rowMap(for: sample, width: 20, scroll: 0, rows: 10)
        // rows: 0 "alpha one", 1 "alpha two", 2 blank, 3 "beta", 4 blank, 5 "gamma one", 6 "", 7 "gamma three", 8 blank
        #expect(map.provenance(atRow: 2) == nil)
        #expect(map.position(row: 2, col: 3) == nil)
        // row 2 is one below "alpha two" and one above "beta": the tie goes below, to the start of "beta"
        #expect(map.nearestPosition(row: 2, col: 3)?.position == at("b", 0, 0))
        // far below everything: the end of the last row that has content
        #expect(map.nearestPosition(row: 9, col: 0)?.position == at("c", 2, 11))
    }
}

@Suite("A selection survives the content scrolling")
struct SelectionScrollTests {
    @Test func `the same selection highlights what is visible and keeps reading the same text at any scroll`() {
        let selection = Selection(anchor: at("a", 1, 6), head: at("c", 0, 5))
        let expected = "two\nbeta\ngamma"
        // Scrolled to the top: the whole selection is visible.
        let top = rowMap(for: sample, width: 20, scroll: 0, rows: 9)
        let topRows = Set(top.highlights(of: selection, in: sample).map(\.row))
        #expect(topRows == [1, 3, 5])
        // Scrolled so that only the later part is visible: the earlier rows are gone, the selection is untouched.
        let scrolled = rowMap(for: sample, width: 20, scroll: 3, rows: 4)
        let scrolledSpans = scrolled.highlights(of: selection, in: sample)
        #expect(Set(scrolledSpans.map(\.row)) == [0, 2])
        #expect(selection.text(in: sample) == expected)
        // Scrolled so that none of it is visible: no highlight, the same text.
        let away = rowMap(for: sample, width: 20, scroll: 6, rows: 3)
        #expect(away.highlights(of: selection, in: sample).isEmpty)
        #expect(selection.text(in: sample) == expected)
    }

    @Test func `a selection made while scrolled maps to the same content as one made at the top`() {
        let atTop = rowMap(for: sample, width: 20, scroll: 0, rows: 9)
        let scrolled = rowMap(for: sample, width: 20, scroll: 3, rows: 4)
        // "beta" is row 3 at the top and row 0 once scrolled by three.
        #expect(atTop.position(row: 3, col: 2)?.position == scrolled.position(row: 0, col: 2)?.position)
    }

    @Test func `re-wrapping at another width keeps the selection on the same graphemes`() {
        let content = TestContent(blocks: [(id: "w", lines: ["the quick brown fox"])])
        let selection = Selection(anchor: at("w", 0, 4), head: at("w", 0, 9))
        for width in [30, 10, 6] {
            let map = rowMap(for: content, width: width, scroll: 0, rows: 8)
            #expect(selection.text(in: content) == "quick")
            let spans = map.highlights(of: selection, in: content)
            let cells = spans.reduce(0) { $0 + ($1.endCol - $1.startCol) }
            #expect(cells == 5, "width \(width) highlighted \(cells) cells")
        }
    }
}

@Suite("The highlight covers the right cells")
struct SelectionHighlightTests {
    @Test func `within one row it starts and ends at the selected graphemes`() {
        let map = rowMap(for: sample, width: 20, scroll: 0, rows: 10, indent: 2)
        let spans = map.highlights(of: Selection(anchor: at("a", 0, 6), head: at("a", 0, 9)), in: sample)
        #expect(spans == [HighlightSpan(row: 0, startCol: 8, endCol: 11)])
    }

    @Test func `across rows the first runs to the end, the middle is whole and the last stops at the head`() {
        let map = rowMap(for: sample, width: 20, scroll: 0, rows: 10)
        let spans = map.highlights(of: Selection(anchor: at("a", 0, 6), head: at("b", 0, 2)), in: sample)
        #expect(
            spans == [
                HighlightSpan(row: 0, startCol: 6, endCol: 9), HighlightSpan(row: 1, startCol: 0, endCol: 9),
                HighlightSpan(row: 3, startCol: 0, endCol: 2)
            ])
    }

    @Test func `wide characters are counted in cells, not graphemes`() {
        let content = TestContent(blocks: [(id: "w", lines: ["日本語abc"])])
        let map = rowMap(for: content, width: 40, scroll: 0, rows: 3, indent: 2)
        let spans = map.highlights(of: Selection(anchor: at("w", 0, 1), head: at("w", 0, 4)), in: content)
        #expect(spans == [HighlightSpan(row: 0, startCol: 4, endCol: 9)])
    }

    @Test func `an empty line has no cells to highlight, and a collapsed or orphaned selection has no highlight`() {
        let map = rowMap(for: sample, width: 20, scroll: 0, rows: 10)
        let across = map.highlights(of: Selection(anchor: at("c", 0, 0), head: at("c", 2, 3)), in: sample)
        #expect(across.map(\.row) == [5, 7])
        #expect(map.highlights(of: Selection(at: at("a", 0, 3)), in: sample).isEmpty)
        #expect(map.highlights(of: Selection(anchor: at("a", 0, 0), head: at("gone", 0, 1)), in: sample).isEmpty)
    }
}

@Suite("Double and triple click select a word and a line")
struct WordAndLineSelectionTests {
    private let content = TestContent(blocks: [(id: "w", lines: ["hello_world foo->bar", ""])])

    @Test func `a word is letters, digits and underscore, whatever the offset inside it`() {
        for offset in [0, 3, 10] {
            let selection = Selection.word(at: at("w", 0, offset), in: content)
            #expect(selection?.text(in: content) == "hello_world", "offset \(offset)")
        }
    }

    @Test func `spaces together and punctuation together are runs of their own`() {
        #expect(Selection.word(at: at("w", 0, 11), in: content)?.text(in: content) == " ")
        #expect(Selection.word(at: at("w", 0, 16), in: content)?.text(in: content) == "->")
        #expect(Selection.word(at: at("w", 0, 18), in: content)?.text(in: content) == "bar")
    }

    @Test func `at the end of the line the last run is chosen`() {
        #expect(Selection.word(at: at("w", 0, 20), in: content)?.text(in: content) == "bar")
    }

    @Test func `a line is the whole line`() {
        #expect(Selection.line(at: at("w", 0, 5), in: content)?.text(in: content) == "hello_world foo->bar")
    }

    @Test func `an empty line, a missing line and a gone block select nothing`() {
        #expect(Selection.word(at: at("w", 1, 0), in: content) == nil)
        #expect(Selection.word(at: at("w", 5, 0), in: content) == nil)
        #expect(Selection.line(at: at("gone", 0, 0), in: content) == nil)
        #expect(Selection.line(at: at("w", -1, 0), in: content) == nil)
    }
}
