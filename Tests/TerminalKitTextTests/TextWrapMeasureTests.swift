import Testing

@testable import TerminalKitText

@Suite("Wrapped text can be measured without being built")
struct TextWrapMeasureTests {
    private static let samples = [
        "", "a", "the quick brown fox", "abcdefghij", "a\n\nb", "tab\tseparated words here", "日本語のテキストを折り返す",
        "emoji 👨‍👩‍👧 family and 🇫🇷 flag",
        "  leading and trailing  ", "exactly ten", "line one\nline two is longer\nthree",
        "e\u{301}combining marks e\u{301}e\u{301}",
        "a very long unbroken-word-that-has-to-be-cut-inside-the-word end"
    ]

    @Test func `the measure is the count and the widest width of the lines that wrapping builds`() {
        for text in Self.samples {
            for width in [1, 2, 3, 5, 10, 11, 40] {
                let lines = TextWrap.lines(text, width: width)
                let measured = TextWrap.measure(text, width: width)
                #expect(measured.rows == lines.count, "rows of \(text.debugDescription) at \(width)")
                #expect(
                    measured.widest == lines.map { UnicodeWidth.displayWidth(of: $0) }.max() ?? 0,
                    "widest of \(text.debugDescription) at \(width)"
                )
            }
        }
    }
}
