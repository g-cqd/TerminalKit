import TerminalKitStyle
import Testing

@testable import TerminalKitRender

/// Between two changed runs on one row, writing the unchanged cells again can be shorter than moving the
/// cursor over them: one byte a space, against six or more for `ESC [ row ; col H`. The diff writes the gap
/// when it is shorter and costs no style change, and moves the cursor otherwise.
@Suite("Short unchanged gaps are written over")
struct DiffGapTests {
    private func frames(front: String, back: String, gapStyle: Style = .default) -> [UInt8] {
        var before = ScreenBuffer(columns: 40, rows: 3)
        before.write(front, row: 1, col: 0, style: .default)
        // The gap keeps its style in both frames, so it is unchanged either way.
        if gapStyle != .default { before.write(" ", row: 1, col: 4, style: gapStyle) }
        var after = before
        after.dirty.clear()
        after.write(String(back.prefix(4)), row: 1, col: 0, style: .default)
        after.write(String(back.dropFirst(5)), row: 1, col: 5, style: .default)
        return Array(DiffRenderer.render(front: before, back: after))
    }

    private func cursorMoves(_ bytes: [UInt8]) -> Int {
        var count = 0
        var index = 0
        while index + 1 < bytes.count {
            if bytes[index] == 0x1B, bytes[index + 1] == 0x5B {
                var end = index + 2
                while end < bytes.count, !(0x40 ... 0x7E).contains(bytes[end]) { end += 1 }
                if end < bytes.count, bytes[end] == 0x48 { count += 1 }
                index = end
            }
            index += 1
        }
        return count
    }

    @Test func `a one-space gap between two changed words is written, not jumped`() {
        let output = frames(front: "word word", back: "WORD WORD")

        #expect(cursorMoves(output) == 1)
        #expect(containsSubsequence(output, Array("WORD WORD".utf8)))
    }

    @Test func `a gap longer than a cursor move is jumped`() {
        let output = frames(front: "a                 b", back: "A                 B")

        #expect(cursorMoves(output) == 2)
    }

    @Test func `a gap in another style is jumped, so no style changes for it`() {
        let output = frames(front: "word word", back: "WORD WORD", gapStyle: Style(inverse: true))

        #expect(cursorMoves(output) == 2)
    }
}
