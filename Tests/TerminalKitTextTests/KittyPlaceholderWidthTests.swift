import Testing

@testable import TerminalKitText

/// A placeholder cell (TerminalKitCodecs' `KittyPlaceholder`) takes one column: `U+10EEEE` is one, and its row and column marks combine into it. A
/// row of them must measure as many columns as it has cells, or an image's row would be cut or padded wrong.
@Suite("A kitty placeholder cell is one column wide")
struct KittyPlaceholderWidthTests {
    /// `U+10EEEE`, then the marks for row and column (kitty's table starts 0305, 030D, 030E, 0310).
    private static let marks: [Unicode.Scalar] = ["\u{0305}", "\u{030D}", "\u{030E}", "\u{0310}"]

    private static func cell(_ row: Int, _ column: Int) -> String {
        var text = "\u{10EEEE}"
        text.unicodeScalars.append(marks[row])
        text.unicodeScalars.append(marks[column])
        return text
    }

    @Test func `one cell is one column, and a row of cells is as wide as its count`() {
        let cell = Self.cell(3, 2)
        #expect(cell.count == 1, "one grapheme")
        #expect(UnicodeWidth.displayWidth(of: cell) == 1)
        let row = (0 ..< 40).map { Self.cell(0, $0 % 4) }.joined()
        #expect(UnicodeWidth.displayWidth(of: row) == 40)
    }
}
