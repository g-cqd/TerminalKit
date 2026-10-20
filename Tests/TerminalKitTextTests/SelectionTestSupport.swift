import Testing

@testable import TerminalKitText

/// Content for the tests: blocks of lines, each block named by a string.
struct TestContent: SelectableContent {
    var blocks: [(id: String, lines: [String])]

    var blockCount: Int { blocks.count }
    func ordinal(of block: String) -> Int? { blocks.firstIndex { $0.id == block } }
    func blockID(at ordinal: Int) -> String { blocks[ordinal].id }
    func lineCount(ofBlockAt ordinal: Int) -> Int { blocks[ordinal].lines.count }
    func line(_ line: Int, ofBlockAt ordinal: Int) -> String { blocks[ordinal].lines[line] }
}

typealias Position = ContentPosition<String>
typealias Selection = ContentSelection<String>

func at(_ block: String, _ line: Int, _ offset: Int) -> Position {
    Position(block: block, line: line, offset: offset)
}

let sample = TestContent(blocks: [
    (id: "a", lines: ["alpha one", "alpha two"]),
    (id: "b", lines: ["beta"]),
    (id: "c", lines: ["gamma one", "", "gamma three"])
])

/// Draws content as rows of at most `width` cells, wrapping by grapheme, with one blank (content-free) row between blocks, then
/// shows `rows` rows from row `scroll`. It is a stand-in for a host's layout, and it records what each row shows.
func rowMap(for content: TestContent, width: Int, scroll: Int, rows: Int, indent: Int = 0) -> RowMap<String> {
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
