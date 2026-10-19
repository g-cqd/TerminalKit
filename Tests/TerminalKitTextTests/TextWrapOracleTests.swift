import Testing

@testable import TerminalKitText

/// The byte-walking `TextWrap` must wrap exactly as the grapheme-by-grapheme version it replaced, which is
/// kept here as the oracle: on the cases that matter and on thousands of generated strings.
@Suite("The fast wrap equals the grapheme wrap")
struct TextWrapOracleTests {
    /// The original implementation (from ask's `TextWrap`), unchanged.
    private enum Reference {
        static func lines(_ text: String, width: Int) -> [String] {
            let width = Swift.max(1, width)
            var lines: [String] = []
            for paragraph in text.replacing("\t", with: "    ").split(separator: "\n", omittingEmptySubsequences: false)
            {
                wrap(paragraph, width: width, into: &lines)
            }
            return lines
        }

        private static func wrap(_ paragraph: Substring, width: Int, into lines: inout [String]) {
            var line = ""
            var lineWidth = 0
            var lastSpace: (index: String.Index, width: Int)?
            for character in paragraph {
                let characterWidth = UnicodeWidth.displayWidth(of: character)
                if lineWidth + characterWidth > width {
                    if character == " " {
                        lines.append(line)
                        (line, lineWidth, lastSpace) = ("", 0, nil)
                        continue
                    }
                    if let space = lastSpace, space.index > line.startIndex {
                        let carried = String(line[line.index(after: space.index)...])
                        lines.append(String(line[..<space.index]))
                        line = carried
                        lineWidth = lineWidth - space.width - 1
                    } else {
                        lines.append(line)
                        line = ""
                        lineWidth = 0
                    }
                    lastSpace = nil
                }
                if character == " " { lastSpace = (line.endIndex, lineWidth) }
                line.append(character)
                lineWidth += characterWidth
            }
            lines.append(line)
        }
    }

    private static let widths = [1, 2, 3, 4, 5, 7, 10, 20, 80]

    @Test(arguments: [
        "", " ", "  ", "a", "the quick brown fox jumps over the lazy dog", " leading and trailing ",
        "one two three four five", "a\n\nb\n", "\n", "\n\n", "tab\tseparated\tvalues", "日本語のテキスト",
        "ab 日本 cd", "e\u{301}e\u{301} e\u{301}", "👨‍👩‍👧 family and ❤️ heart", "cr\r\nlf and\rbare", "x\r\n",
        "\r\n\r\n", "nul\u{0}inside", "👍🏽 ok", "flag 🇫🇷🇩🇪 pair", "a\u{200B}b", "\u{301}orphan mark", "\n日本",
        "end\n日", "a\n\u{301}", String(repeating: "word ", count: 50), String(repeating: "x", count: 300)
    ])
    func `a hand-picked text wraps as it did`(text: String) {
        for width in Self.widths { #expect(TextWrap.lines(text, width: width) == Reference.lines(text, width: width)) }
    }

    @Test func `generated texts wrap as they did`() {
        let pieces: [String] = [
            "a", "b", "word", " ", " ", " ", "\n", "\t", "\r", "\r\n", "日", "本", "é", "e\u{301}", "\u{301}", "👨‍👩‍👧",
            "❤️", "1️⃣", "🇫🇷", "🇫", "👍🏽", "\u{0}", "\u{200B}", "—", "✓", "ï", "ab cd ef"
        ]
        var state: UInt64 = 0x2545_F491_4F6C_DD1D
        func random(_ bound: Int) -> Int {
            state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            return Int(state >> 33) % bound
        }
        for _ in 0 ..< 3_000 {
            var text = ""
            for _ in 0 ..< random(40) { text += pieces[random(pieces.count)] }
            let width = Self.widths[random(Self.widths.count)]
            let expected = Reference.lines(text, width: width)
            let actual = TextWrap.lines(text, width: width)
            #expect(actual == expected, "width \(width), text \(text.debugDescription)")
            if actual != expected { return }
        }
    }
}
