import Testing

@testable import TerminalKitCodecs

@Suite
struct EscapeSequencesTests {
    @Test
    func `Sync output markers`() {
        // CSI ? 2026 h
        #expect(EscapeSequences.beginSyncUpdate == [0x1b, 0x5b, 0x3f, 0x32, 0x30, 0x32, 0x36, 0x68])
        #expect(EscapeSequences.endSyncUpdate == [0x1b, 0x5b, 0x3f, 0x32, 0x30, 0x32, 0x36, 0x6c])
    }

    @Test
    func `Push keyboard mode`() {
        let bytes = EscapeSequences.pushKeyboardMode(flags: 31)
        // CSI > 31 u
        #expect(bytes == [0x1b, 0x5b, 0x3e, 0x33, 0x31, 0x75])
    }

    @Test
    func `Move cursor`() {
        let bytes = EscapeSequences.moveCursor(row: 5, col: 10)
        // CSI 5 ; 10 H
        #expect(bytes == [0x1b, 0x5b, 0x35, 0x3b, 0x31, 0x30, 0x48])
    }

    @Test(arguments: [
        (-5, 0, "\u{1B}[1;1H"),
        (65_535, 65_535, "\u{1B}[65535;65535H"),
        (70_000, 80_000, "\u{1B}[65535;65535H")
    ])
    func `Move cursor clamps edge values`(row: Int, col: Int, expectedSequence: String) {
        #expect(EscapeSequences.moveCursor(row: row, col: col) == Array(expectedSequence.utf8))
    }
}
