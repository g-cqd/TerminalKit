import Testing

@testable import TerminalKitRender
@testable import TerminalKitStyle

/// Roadmap 0007: a screen buffer stores 16-byte cells compared as integers, and nothing a caller reads or the
/// terminal receives changes because of it.
@Suite("Cells are packed into sixteen bytes")
struct PackedCellTests {
    private let family: Character = "\u{1F468}\u{200D}\u{1F469}\u{200D}\u{1F467}\u{200D}\u{1F466}"  // 25 UTF-8 bytes

    @Test func `a cell is sixteen bytes`() {
        #expect(MemoryLayout<PackedCell>.stride == 16)
    }

    @Test func `a cell reads back as it was stored, whatever its grapheme and style`() {
        let style = Style(
            fg: .rgb(r: 1, g: 2, b: 3), bg: .indexed(200), underlineColor: .indexed(9), bold: true,
            italic: true, underline: .curly, inverse: true)
        for character: Character in ["a", "é", "e\u{301}", "漢", "\u{1F1EB}\u{1F1F7}", "👍🏽", family] {
            var buffer = ScreenBuffer(columns: 4, rows: 1)
            buffer[0, 0] = Cell(character: character, style: style, width: 2)

            #expect(buffer[0, 0] == Cell(character: character, style: style, width: 2))
            #expect(buffer[0, 0].character.utf8.elementsEqual(character.utf8))
        }
    }

    @Test func `a grapheme longer than eight bytes reaches the terminal whole`() {
        var buffer = ScreenBuffer(columns: 4, rows: 1)
        buffer.write(String(family), row: 0, col: 0, style: .default)

        let output = DiffRenderer.render(front: ScreenBuffer(columns: 4, rows: 1), back: buffer)

        #expect(output.split(separator: 0x1B).contains { $0.elementsEqual(Array("[1;1H".utf8) + Array(family.utf8)) })
    }

    @Test func `the same style written to two buffers compares equal`() {
        // Ids come from one table for every buffer, so a front and a back buffer agree on them.
        let style = Style(fg: .indexed(3), bold: true)
        var front = ScreenBuffer(columns: 8, rows: 1)
        var back = ScreenBuffer(columns: 8, rows: 1)
        front.write("same", row: 0, col: 0, style: style)
        back.write("same", row: 0, col: 0, style: style)

        #expect(DiffRenderer.render(front: front, back: back).isEmpty)
    }

    @Test func `two spellings of one character are two cells`() {
        // `Character` equality is canonical equivalence; the bytes a terminal receives are not. A cell now
        // compares by bytes, so changing the spelling is redrawn.
        var buffer = ScreenBuffer(columns: 2, rows: 1)
        buffer.write("\u{E9}", row: 0, col: 0, style: .default)
        buffer.dirty.clear()

        buffer.write("e\u{301}", row: 0, col: 0, style: .default)

        #expect(!buffer.dirty.isEmpty)
    }
}
