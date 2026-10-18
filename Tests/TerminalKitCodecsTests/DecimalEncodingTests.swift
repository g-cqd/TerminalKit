import Testing

@testable import TerminalKitCodecs

/// Numbers in escape sequences, checked against the standard library for every value a coordinate can take.
@Suite("Escape-sequence numbers are exact for every coordinate")
struct DecimalEncodingTests {
    @Test func `every coordinate from 1 to 65535 encodes exactly as its decimal digits`() {
        var bytes = ContiguousArray<UInt8>()
        for value in 1 ... 65_535 {
            bytes.removeAll(keepingCapacity: true)
            EscapeSequences.appendMoveCursor(row: value, col: value, to: &bytes)
            let expected = Array("\u{1B}[\(value);\(value)H".utf8)
            guard Array(bytes) == expected else {
                Issue.record("value \(value) encoded as \(String(decoding: bytes, as: UTF8.self).debugDescription)")
                return
            }
        }
    }

    @Test func `out-of-range coordinates are clamped, not wrapped`() {
        var bytes = ContiguousArray<UInt8>()
        EscapeSequences.appendMoveCursor(row: 0, col: 70_000, to: &bytes)
        #expect(Array(bytes) == Array("\u{1B}[1;65535H".utf8))
    }

    @Test func `the digit table covers only what terminals use`() {
        #expect(EscapeSequences.decimalTableCount == 1_000)
    }
}
