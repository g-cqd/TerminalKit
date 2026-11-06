/// kitty's Unicode image placeholders (kitty's graphics protocol, "Unicode placeholders"; roadmap 0208 in ask).
///
/// An image given a virtual placement (``GraphicsCommand/Placement/isVirtual``) is drawn wherever cells hold `U+10EEEE` with a mark
/// for the cell's row and one for its column, in a foreground colour that names the image. Those cells are text to the screen: they
/// scroll, wrap, fold, clear and diff as any row does, which an image placed at the cursor does not. A terminal without the protocol
/// shows them as unknown characters, so a host draws them only where the terminal answered the graphics query.
public enum KittyPlaceholder {
    /// The character every cell starts with.
    public static let character: Unicode.Scalar = "\u{10EEEE}"

    /// The largest row or column a cell can say: the table has one mark per number.
    public static var maximumIndex: Int { KittyPlaceholderDiacritics.all.count - 1 }

    /// The cell at `row` and `column` of an image's placement; nil past ``maximumIndex`` or below zero, rather than a wrong piece.
    public static func cell(row: Int, column: Int) -> String? {
        guard let rowMark = mark(row), let columnMark = mark(column) else { return nil }
        var text = String(Character(character))
        text.unicodeScalars.append(rowMark)
        text.unicodeScalars.append(columnMark)
        return text
    }

    /// The foreground colour that names image `id`: its low 24 bits, red the highest byte.
    public static func color(for id: UInt32) -> (red: UInt8, green: UInt8, blue: UInt8) {
        (UInt8((id >> 16) & 0xFF), UInt8((id >> 8) & 0xFF), UInt8(id & 0xFF))
    }

    private static func mark(_ index: Int) -> Unicode.Scalar? {
        guard index >= 0, index <= maximumIndex else { return nil }
        return Unicode.Scalar(KittyPlaceholderDiacritics.all[index])
    }
}
