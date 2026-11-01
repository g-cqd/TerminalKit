import TerminalKitStyle
import TerminalKitText
import Testing

@testable import TerminalKitMarkdown

/// The glyphs a wrap reads its pieces as are their graphemes, whichever path reads them: a piece of printable ASCII byte by byte,
/// the rest grapheme by grapheme. The reference is the grapheme walk itself, over tricky pieces and seeded random ones.
struct RowWrapGlyphTests {
    static let tricky = [
        "", " ", "let x = 1 // c", "a\tb", "\r\n", "a\r\nb", "\u{1B}[0m", "\u{7F}", "e\u{301}", "a\u{301}b", "界 x",
        "😀 a",
        "\u{600}1", "a\u{200D}b", "👨‍👩‍👧", "  indent", "\u{85}x"
    ]
    static let alphabet = [
        "a", "Z", "0", " ", " ", "~", "{", "\t", "\r", "\n", "\u{1B}", "\u{7F}", "\u{301}", "é", "界", "😀", "\u{600}"
    ]

    static func pieces() -> [[Piece]] {
        var state: UInt64 = 0x5EED
        func next() -> UInt64 {
            state &+= 0x9E37_79B9_7F4A_7C15
            var value = state
            value = (value ^ (value >> 30)) &* 0xBF58_476D_1CE4_E5B9
            value = (value ^ (value >> 27)) &* 0x94D0_49BB_1331_11EB
            return value ^ (value >> 31)
        }
        func piece(_ text: String) -> Piece { Piece(text: text, style: Style(), source: nil, isVerbatim: true) }
        var result = [tricky.map(piece)]
        for _ in 0 ..< 3_000 {
            result.append(
                (0 ..< Int(next() % 4))
                    .map { _ in
                        if next() % 6 == 0 {
                            return Piece(text: "", style: Style(), source: nil, isVerbatim: false, isBreak: true)
                        }
                        // Most pieces are plain ASCII, as code is.
                        let pool = next() % 2 == 0 ? Array(alphabet.prefix(7)) : alphabet
                        return piece(
                            (0 ..< Int(next() % 12)).map { _ in pool[Int(next() % UInt64(pool.count))] }.joined())
                    })
        }
        return result
    }

    /// The glyphs as the grapheme walk reads them, as a string to compare.
    static func reference(_ pieces: [Piece]) -> [String] {
        var glyphs: [String] = []
        for (index, piece) in pieces.enumerated() {
            if piece.isBreak {
                glyphs.append("-1 0 0 0 false")
                continue
            }
            var offset = 0
            for character in piece.text {
                let count = character.utf8.count
                defer { offset += count }
                if character.unicodeScalars.contains(where: TextSanitizer.isControl) { continue }
                let width = character.isASCII ? 1 : UnicodeWidth.displayWidth(of: character)
                glyphs.append("\(index) \(offset) \(offset + count) \(width) \(character == " ")")
            }
        }
        return glyphs
    }

    @Test func `the glyphs of a wrap are its pieces' graphemes`() {
        for pieces in Self.pieces() {
            let glyphs = RowWrap(pieces).glyphs.map { "\($0.piece) \($0.start) \($0.end) \($0.width) \($0.isSpace)" }
            #expect(glyphs == Self.reference(pieces), "\(pieces.map { $0.text.unicodeScalars.map(\.value) })")
        }
    }
}
