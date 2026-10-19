import TerminalKitStyle
import Testing

@testable import TerminalKitIO
@testable import TerminalKitRender

/// Roadmap 0011: a bottom-aligned transcript shifts every row when a line arrives. With the transcript's rows
/// declared as a scroll region, the pipeline finds the shift itself and moves the terminal's rows with
/// DECSTBM and SU or SD, so only the new line is drawn. Every terminal since the VT100 has both.
@Suite("A scroll region turns a streamed line into a scroll")
@MainActor
struct ScrollRegionDetectionTests {
    private static let columns = 24
    private static let rows = 8
    private let mock = MockTerminalConnection(size: TerminalSize(columns: columns, rows: rows))
    private let pipeline: RenderPipeline
    private var screen = ScreenEmulator(columns: columns, rows: rows)

    init() {
        pipeline = RenderPipeline(connection: mock, columns: Self.columns, rows: Self.rows)
    }

    /// A line unlike its neighbours in every column, so a redraw of it cannot hide in a short diff.
    private func line(_ number: Int) -> String {
        String(repeating: String(UnicodeScalar(UInt8(65 + number % 26))), count: Self.columns - 4) + " \(number)"
    }

    private func padded(_ text: String) -> String {
        text + String(repeating: " ", count: max(0, Self.columns - text.count))
    }

    /// Draws transcript lines `first ..< first + rows - 1` and a status row, flushes, and replays the output.
    private mutating func frame(firstLine first: Int, status: String = "status") throws -> [UInt8] {
        pipeline.beginFrame()
        for offset in 0 ..< Self.rows - 1 {
            pipeline.buffer.write(
                padded(line(first + offset)),
                row: offset, col: 0, style: .default)
        }
        pipeline.buffer.write(
            padded(status),
            row: Self.rows - 1, col: 0, style: .default)
        mock.clearOutput()
        try pipeline.flush()
        let output = mock.writtenOutput
        screen.feed(output)
        return output
    }

    private var expected: [String] {
        (0 ..< Self.rows)
            .map { row in
                (0 ..< Self.columns).map { String(pipeline.buffer[row, $0].character) }.joined()
            }
    }

    @Test mutating func `a streamed line is one scroll and one new row`() throws {
        pipeline.scrollRegion = 0 ..< Self.rows - 1
        _ = try frame(firstLine: 0)

        let output = try frame(firstLine: 1)

        #expect(containsSubsequence(output, Array("\u{1B}[1;7r\u{1B}[1S".utf8)))
        #expect(!containsSubsequence(output, Array(line(3).utf8)), "a row that only moved was redrawn")
        // The new row's letters; the space before its number matches the blank row the scroll exposed.
        #expect(containsSubsequence(output, Array(line(7).prefix(Self.columns - 4).utf8)))
        #expect(screen.lines == expected)
    }

    @Test mutating func `without a scroll region, the same frame redraws every row`() throws {
        _ = try frame(firstLine: 0)

        let output = try frame(firstLine: 1)

        #expect(!containsSubsequence(output, Array("\u{1B}[1S".utf8)))
        #expect(screen.lines == expected)
    }

    @Test mutating func `several new lines are one scroll`() throws {
        pipeline.scrollRegion = 0 ..< Self.rows - 1
        _ = try frame(firstLine: 0)

        let output = try frame(firstLine: 3)

        #expect(containsSubsequence(output, Array("\u{1B}[3S".utf8)))
        #expect(screen.lines == expected)
    }

    @Test mutating func `scrolling back through the transcript scrolls the other way`() throws {
        pipeline.scrollRegion = 0 ..< Self.rows - 1
        _ = try frame(firstLine: 10)

        let output = try frame(firstLine: 8)

        #expect(containsSubsequence(output, Array("\u{1B}[2T".utf8)))
        #expect(screen.lines == expected)
    }

    @Test mutating func `a change that is not a shift does not scroll`() throws {
        pipeline.scrollRegion = 0 ..< Self.rows - 1
        _ = try frame(firstLine: 0)

        let typed = try frame(firstLine: 0, status: "status, typing")
        let replaced = try frame(firstLine: 100)

        #expect(!containsSubsequence(typed, Array("\u{1B}[1;7r".utf8)))
        #expect(!containsSubsequence(replaced, Array("\u{1B}[1;7r".utf8)))
        #expect(screen.lines == expected)
    }

    @Test mutating func `a long run of mixed frames keeps the screen right`() throws {
        // The pipeline keeps row hashes from flush to flush; edits between scrolls, a redraw, and an explicit
        // hint must all leave them describing the screen, or a later scroll would pick the wrong shift.
        pipeline.scrollRegion = 0 ..< Self.rows - 1
        _ = try frame(firstLine: 0)
        for step in 1 ... 12 {
            switch step % 4 {
                case 0:
                    pipeline.beginFrame()
                    pipeline.buffer.write("edited", row: step % (Self.rows - 1), col: 2, style: .default)
                    mock.clearOutput()
                    try pipeline.flush()
                    screen.feed(mock.writtenOutput)
                case 1:
                    try pipeline.forceRedraw()
                    _ = try frame(firstLine: step)
                default:
                    _ = try frame(firstLine: step)
            }
            #expect(screen.lines == expected, "step \(step)")
        }
        _ = try frame(firstLine: 40)
        #expect(screen.lines == expected)
    }

    @Test mutating func `an explicit hint still wins`() throws {
        pipeline.scrollRegion = 0 ..< Self.rows - 1
        _ = try frame(firstLine: 0)

        pipeline.scrollHint = ScrollHint(regionTop: 0, regionHeight: Self.rows - 1, delta: 1)
        let output = try frame(firstLine: 1)

        #expect(containsSubsequence(output, Array("\u{1B}[1;7r\u{1B}[1S".utf8)))
        #expect(screen.lines == expected)
    }
}
