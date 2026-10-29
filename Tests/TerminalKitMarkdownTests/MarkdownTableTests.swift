import TerminalKitStyle
import Testing

@testable import TerminalKitMarkdown

@Suite("Tables fit the width: natural columns, then shared, then one record per row")
struct MarkdownTableTests {
    private let table =
        "| Name | Size | Notes |\n| :--- | ---: | :---: |\n| alpha | 1 | the first row |\n| b | 22 | x |\n"

    @Test func `a table that fits takes its columns' natural widths, aligned`() {
        let rows = Rendered.rows(table)
        #expect(rows[0] == "Name  │ Size │     Notes    ")
        #expect(rows[1] == "──────┼──────┼──────────────")
        #expect(rows[2] == "alpha │    1 │ the first row")
        #expect(rows[3] == "b     │   22 │       x      ")
    }

    @Test(arguments: 20 ... 27)
    func `a narrower table wraps its cells inside columns at least as wide as their words`(width: Int) {
        let rows = Rendered.lines(table, width: width)
        #expect(rows.allSatisfy { $0.width <= width })
        #expect(rows[1].text.contains("┼"))
    }

    @Test func `a table too wide for its words becomes a record per body row`() {
        #expect(
            Rendered.rows(table, width: 14) == [
                "Name: alpha", "Size: 1", "Notes: the", "first row", "", "Name: b", "Size: 22", "Notes: x"
            ])
    }

    @Test func `share keeps each column between its least and natural width and fills what is available`() {
        let widths = BlockWriter.share(20, least: [3, 2, 5], natural: [10, 2, 20])
        #expect(widths.reduce(0, +) == 20)
        #expect(zip(widths, [3, 2, 5]).allSatisfy { $0 >= $1 })
        #expect(zip(widths, [10, 2, 20]).allSatisfy { $0 <= $1 })
        #expect(BlockWriter.share(10, least: [3, 4], natural: [3, 4]) == [3, 4])
    }

    @Test func `padded aligns left, centre and right`() {
        let cell = [StyledRun("ab", style: .default)]
        #expect(StyledLine(BlockWriter.padded(cell, to: 5, alignment: 1)).text == "ab   ")
        #expect(StyledLine(BlockWriter.padded(cell, to: 5, alignment: 2)).text == " ab  ")
        #expect(StyledLine(BlockWriter.padded(cell, to: 5, alignment: 3)).text == "   ab")
    }
}
