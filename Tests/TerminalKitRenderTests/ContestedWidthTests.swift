import TerminalKitStyle
import Testing

@testable import TerminalKitRender
@testable import TerminalKitText

/// Roadmap 0013: terminals disagree on some graphemes' widths. Measured: Terminal.app draws a ZWJ family 8
/// columns wide, wezterm draws a VS16 heart 1 column wide, where kitty and ghostty draw both 2. The diff
/// cannot know which terminal it writes to, so after such a grapheme it moves the cursor to where the next
/// cell belongs; the rest of the row lands right everywhere (checked on all four).
@Suite("The diff realigns after a grapheme terminals disagree on")
struct ContestedWidthTests {
    private let family = "\u{1F468}\u{200D}\u{1F469}\u{200D}\u{1F467}"

    private func diff(_ text: String) -> String {
        var back = ScreenBuffer(columns: 20, rows: 2)
        back.write(text, row: 1, col: 0, style: .default)
        return String(
            decoding: DiffRenderer.render(front: ScreenBuffer(columns: 20, rows: 2), back: back), as: UTF8.self)
    }

    @Test func `the cell after a contested grapheme is placed with a cursor move`() {
        #expect(diff(family + "Z").contains(family + "\u{1B}[2;3HZ"))
        #expect(diff("\u{2764}\u{FE0F}Z").contains("\u{2764}\u{FE0F}\u{1B}[2;3HZ"))
        #expect(diff("\u{1F1EB}Z").contains("\u{1F1EB}\u{1B}[2;3HZ"))
    }

    @Test func `graphemes every terminal agrees on need no move`() {
        #expect(diff("\u{4E2D}Z").contains("\u{4E2D}Z"))
        #expect(diff("\u{1F600}Z").contains("\u{1F600}Z"))
        #expect(diff("\u{1F1EB}\u{1F1F7}Z").contains("\u{1F1EB}\u{1F1F7}Z"))
    }

    @Test func `a run after a contested grapheme is placed, not bridged as a gap`() {
        var front = ScreenBuffer(columns: 20, rows: 2)
        front.write("ab", row: 1, col: 2, style: .default)
        var back = front
        back.dirty.clear()
        back.write(family, row: 1, col: 0, style: .default)
        back.write("c", row: 1, col: 3, style: .default)

        let output = String(decoding: DiffRenderer.render(front: front, back: back), as: UTF8.self)

        #expect(output.contains(family + "\u{1B}[2;4Hc"))
    }

    @Test func `a full redraw realigns too`() {
        var buffer = ScreenBuffer(columns: 20, rows: 2)
        buffer.write(family + "Z", row: 0, col: 0, style: .default)

        let output = String(decoding: DiffRenderer.renderFull(buffer), as: UTF8.self)

        #expect(output.contains(family + "\u{1B}[1;3HZ"))
    }

    @Test func `the contested set is the one the terminals disagreed on`() {
        let contested: [Character] = [
            Character(family), "\u{2764}\u{FE0F}", "1\u{FE0F}\u{20E3}", "\u{1F1EB}", "\u{AD}", "\u{1F44D}\u{1F3FD}"
        ]
        let agreed: [Character] = ["A", "\u{4E2D}", "\u{1F600}", "\u{2764}", "\u{1F1EB}\u{1F1F7}", "e\u{301}"]
        #expect(contested.allSatisfy(UnicodeWidth.isContested))
        #expect(!agreed.contains(where: UnicodeWidth.isContested))
    }
}
