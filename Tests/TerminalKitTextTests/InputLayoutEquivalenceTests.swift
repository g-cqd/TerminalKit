import Testing

@testable import TerminalKitText

/// The layout's fast path for runs of printable ASCII lays a draft out exactly as walking it grapheme by grapheme does (ask roadmap
/// 0151): the same rows and the same cell for every offset, at every width and first-row indent.
@Suite("The ASCII fast path lays text out as the grapheme walk does")
struct InputLayoutEquivalenceTests {
    /// The layout as it was built before the fast path, one grapheme at a time: the reference.
    private static func reference(
        _ text: String,
        columns: Int,
        firstRowIndent: Int,
        tabSize: Int = 4
    ) -> (rows: [String], carets: [InputLayout.Position]) {
        let columns = max(1, columns)
        let indent = min(max(0, firstRowIndent), columns - 1)
        var rows = [""]
        var carets: [InputLayout.Position] = []
        var column = indent
        for character in text {
            if character.isNewline {
                carets.append(
                    column >= columns
                        ? InputLayout.Position(row: rows.count, column: 0)
                        : InputLayout.Position(row: rows.count - 1, column: column)
                )
                rows.append("")
                column = 0
                continue
            }
            var shown = character
            if character != "\t", character.unicodeScalars.contains(where: TextSanitizer.isControl) { shown = "�" }
            let width = UnicodeWidth.displayWidth(of: shown)
            if width > columns { shown = "?" }
            func measured(at column: Int) -> Int {
                character == "\t" ? min(tabSize - column % tabSize, columns) : min(width, columns)
            }
            if column >= columns || measured(at: column) > columns - column {
                rows.append("")
                column = 0
            }
            carets.append(InputLayout.Position(row: rows.count - 1, column: column))
            let used = measured(at: column)
            if character == "\t" {
                rows[rows.count - 1] += String(repeating: " ", count: used)
            } else {
                rows[rows.count - 1].append(shown)
            }
            column += used
        }
        if column >= columns {
            rows.append("")
            column = 0
        }
        carets.append(InputLayout.Position(row: rows.count - 1, column: column))
        return (rows, carets)
    }

    private static let pieces = [
        "a", "word ", "x", " ", "\t", "\n", "\r\n", "e\u{301}", "\u{301}", "漢", "🙂", "🇫🇷", "\u{7}", "\u{7F}", "é",
        "ab\u{200D}",
        "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", "~", "\r", "z\u{FE0F}"
    ]

    @Test func `random drafts lay out the same at every width and indent`() {
        var state: UInt64 = 0x0151
        func next(_ bound: Int) -> Int {
            state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            return Int(state >> 33) % bound
        }
        for _ in 0 ..< 600 {
            let text = (0 ..< next(40)).map { _ in Self.pieces[next(Self.pieces.count)] }.joined()
            let columns = 1 + next(30)
            let indent = next(4)
            let layout = InputLayout(text, columns: columns, firstRowIndent: indent)
            let expected = Self.reference(text, columns: columns, firstRowIndent: indent)
            #expect(layout.rows == expected.rows, "\(text.debugDescription) at \(columns), indent \(indent)")
            for offset in expected.carets.indices where layout.position(at: offset) != expected.carets[offset] {
                Issue.record(
                    "offset \(offset) of \(text.debugDescription) at \(columns): \(layout.position(at: offset))"
                )
                break
            }
        }
    }
}
