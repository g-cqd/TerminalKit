import Testing

@testable import TerminalKitText

/// A string's width is the sum of its characters' widths, whichever path measures it: printable ASCII, every byte one
/// column, or the grapheme walk for the rest. Tricky strings, then seeded random ones mixing ASCII with controls, CRLF,
/// combining marks, wide characters and emoji.
struct UnicodeWidthStringTests {
    static let tricky = [
        "", " ", "~", "abc", "let x = 1 // c", "\t", "a\tb", "\r\n", "a\r\nb", "\u{0}", "a\u{0}b", "\u{7F}", "e\u{301}",
        "ae\u{301}", "\u{301}", "界", "a界b", "😀", "a😀", "👍🏽", "👨‍👩‍👧", "❤️", "1️⃣", "🇫🇷", "x\u{200B}y", "\u{1B}[0m"
    ]
    static let alphabet = [
        "a", "Z", "0", " ", "~", "!", "\t", "\r", "\n", "\u{0}", "\u{7F}", "\u{301}", "é", "界", "😀", "\u{200D}",
        "\u{FE0F}"
    ]

    static func strings() -> [String] {
        var state: UInt64 = 0x5EED
        func next() -> UInt64 {
            state &+= 0x9E37_79B9_7F4A_7C15
            var value = state
            value = (value ^ (value >> 30)) &* 0xBF58_476D_1CE4_E5B9
            value = (value ^ (value >> 27)) &* 0x94D0_49BB_1331_11EB
            return value ^ (value >> 31)
        }
        var strings = tricky
        for _ in 0 ..< 5_000 {
            strings.append(
                (0 ..< Int(next() % 16)).map { _ in alphabet[Int(next() % UInt64(alphabet.count))] }.joined()
            )
        }
        return strings
    }

    @Test func `a string's width is the sum of its characters' widths`() {
        for string in Self.strings() {
            let sum = string.reduce(0) { $0 + UnicodeWidth.displayWidth(of: $1) }
            #expect(UnicodeWidth.displayWidth(of: string) == sum, "\(string.unicodeScalars.map(\.value))")
        }
    }

    @Test func `printable ASCII is one column a byte`() {
        let printable = String(decoding: Array(0x20 ... 0x7E), as: UTF8.self)
        #expect(UnicodeWidth.displayWidth(of: printable) == 95)
        #expect(UnicodeWidth.displayWidth(of: "a\u{0}b") == 2)
        #expect(UnicodeWidth.displayWidth(of: "e\u{301}") == 1)
    }
}
