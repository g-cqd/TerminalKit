import Testing

@testable import TerminalKitText

/// The rope as a line source: its lines lent across its leaves. A string's lines (`TextLines`) are tested in aemi, with their code.
struct LineSourceTests {
    /// Every line of `source`, read through `withLineBytes`, as a string.
    private static func lines(of source: some LineSource) -> [String] {
        (0 ..< source.lineCount)
            .map { index in
                source.withLineBytes(at: index) { bytes in
                    bytes.withUnsafeBufferPointer { String(decoding: $0, as: UTF8.self) }
                }
            }
    }

    @Test
    func `a rope lends each line, one that runs across leaves included`() {
        // Lines of up to three leaves' length, so some start, end or run across a leaf boundary.
        let text = (0 ..< 40).map { String(repeating: "é\($0)", count: $0 * 13) }.joined(separator: "\r\n") + "\n"
        let rope = Rope(text)

        #expect(Self.lines(of: rope) == (0 ..< rope.lineCount).map { rope.line(at: $0) })
        #expect(rope.lineCount == 41)
    }
}
