import Testing

@testable import TerminalKitText

/// A row of rendered Markdown: `- a **bold** &amp;` and `next` on the line below, drawn as `• a bold & next` (the marker is chrome, the stars
/// hidden, the entity decoded, the soft break a space of chrome).
@Suite("A row of several segments maps cells to content and back")
struct RowSegmentTests {
    let content = TestContent(blocks: [(id: "m", lines: ["- a **bold** &amp;", "next"])])

    func map() -> RowMap<String> {
        var map = RowMap<String>()
        map.reset(rowCount: 1)
        map.set(
            row: 0,
            to: RowProvenance(
                block: "m", ordinal: 0,
                segments: [
                    RowSegment(line: 0, firstOffset: 2, col: 2, text: "a "),  // cells 2, 3
                    RowSegment(line: 0, firstOffset: 6, col: 4, text: "bold"),  // cells 4 to 7
                    RowSegment(line: 0, firstOffset: 12, col: 8, text: " "),  // cell 8
                    RowSegment(line: 0, firstOffset: 13, col: 9, text: "&", sourceCount: 5),  // cell 9
                    RowSegment(line: 1, firstOffset: 0, col: 11, text: "next")  // cells 11 to 14
                ]))
        return map
    }

    @Test func `a cell maps to the grapheme of its segment, a chrome cell to the start or end around it`() {
        let map = map()
        #expect(map.position(row: 0, col: 0)?.position == at("m", 0, 2))
        #expect(map.position(row: 0, col: 5)?.position == at("m", 0, 7))
        #expect(map.position(row: 0, col: 5, edge: .trailing)?.position == at("m", 0, 8))
        // At a segment's edge, the hidden stars beside it come with it.
        #expect(map.position(row: 0, col: 4)?.position == at("m", 0, 4))
        #expect(map.position(row: 0, col: 7, edge: .trailing)?.position == at("m", 0, 12))
        #expect(map.position(row: 0, col: 9)?.position == at("m", 0, 13))
        #expect(map.position(row: 0, col: 9, edge: .trailing)?.position == at("m", 0, 18))
        #expect(map.position(row: 0, col: 10)?.position == at("m", 0, 18))
        #expect(map.position(row: 0, col: 12)?.position == at("m", 1, 1))
        #expect(map.position(row: 0, col: 40)?.position == at("m", 1, 4))
    }

    @Test func `a selection copies the source it spans, hidden markers and all`() {
        let map = map()
        guard let start = map.position(row: 0, col: 4)?.position,
            let end = map.position(row: 0, col: 9, edge: .trailing)?.position
        else {
            Issue.record("no positions")
            return
        }
        #expect(Selection(anchor: start, head: end).text(in: content) == "**bold** &amp;")
    }

    @Test
    func `a highlight covers the selected cells, the chrome between selected segments, and an atomic segment whole`() {
        let map = map()
        let across = Selection(anchor: at("m", 0, 7), head: at("m", 1, 2))
        #expect(map.highlights(of: across, in: content) == [HighlightSpan(row: 0, startCol: 5, endCol: 13)])
        let inside = Selection(anchor: at("m", 0, 14), head: at("m", 0, 15))
        #expect(map.highlights(of: inside, in: content) == [HighlightSpan(row: 0, startCol: 9, endCol: 10)])
        let split = Selection(anchor: at("m", 0, 2), head: at("m", 0, 3))
        #expect(map.highlights(of: split, in: content) == [HighlightSpan(row: 0, startCol: 2, endCol: 3)])
    }

    @Test func `a drag past the row snaps to the end of its last segment`() {
        var map = RowMap<String>()
        map.reset(rowCount: 2)
        map.set(row: 0, to: self.map().provenance(atRow: 0)!)
        #expect(map.nearestPosition(row: 1, col: 0)?.position == at("m", 1, 4))
    }
}
