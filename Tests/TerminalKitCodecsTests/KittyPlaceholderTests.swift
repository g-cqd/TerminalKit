import Testing

@testable import TerminalKitCodecs

/// kitty's Unicode image placeholders: a cell is `U+10EEEE` with a mark for its row and one for its column, and its foreground
/// colour names the image. Cells drawn like text scroll, wrap and clear with it, which an image placed at the cursor does not.
@Suite("Unicode image placeholders: the cell for a row and column, and the colour for an image")
struct KittyPlaceholderTests {
    @Test func `a cell is the placeholder with its row's mark, then its column's`() {
        #expect(KittyPlaceholder.cell(row: 0, column: 0) == "\u{10EEEE}\u{0305}\u{0305}")
        #expect(KittyPlaceholder.cell(row: 1, column: 2) == "\u{10EEEE}\u{030D}\u{030E}")
        #expect(KittyPlaceholder.maximumIndex == 296)
        #expect(KittyPlaceholder.cell(row: 296, column: 0) != nil)
        #expect(KittyPlaceholder.cell(row: 297, column: 0) == nil, "past the table: nothing, not a wrong piece")
        #expect(KittyPlaceholder.cell(row: -1, column: 0) == nil)
    }

    @Test func `the colour carries the image id, 24 bits`() {
        let color = KittyPlaceholder.color(for: 0x12_34_56)
        #expect([color.red, color.green, color.blue] == [0x12, 0x34, 0x56])
    }

    @Test func `a virtual placement asks for placeholders`() {
        var command = GraphicsCommand(action: .placement, id: 7)
        command.placement = GraphicsCommand.Placement(id: 1, columns: 10, rows: 4)
        command.placement?.isVirtual = true
        let text = String(decoding: GraphicsEncoder.encode(command), as: UTF8.self)
        #expect(
            text.contains("U=1") && text.contains("c=10") && text.contains("r=4") && text.contains("i=7"),
            "\(text)"
        )
    }
}
