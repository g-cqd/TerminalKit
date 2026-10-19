import Testing

@testable import TerminalKitText

/// The generated table must say what the toolchain's Unicode properties say, for every scalar, or a newer
/// toolchain's data would silently disagree with it (Scripts/generate-unicode-width-table.swift).
@Suite("The width table matches the toolchain's Unicode properties")
struct UnicodeWidthTableTests {
    private static let residualWide: [ClosedRange<UInt32>] = [
        0x1100 ... 0x115F, 0x2E80 ... 0x303E, 0x3041 ... 0x33BF, 0xA000 ... 0xA4CF, 0xAC00 ... 0xD7AF,
        0xFE30 ... 0xFE6F, 0xFF01 ... 0xFF60, 0xFFE0 ... 0xFFE6
    ]

    private static func expected(_ value: UInt32) -> UInt8 {
        guard let scalar = Unicode.Scalar(value) else { return 0 }
        let properties = scalar.properties
        var bits: UInt8 = 0
        if properties.isIdeographic || residualWide.contains(where: { $0.contains(value) }) { bits |= 1 }
        if properties.generalCategory == .nonspacingMark || properties.generalCategory == .enclosingMark
            || properties.isDefaultIgnorableCodePoint || (0x1160 ... 0x11FF).contains(value)
            || (0xD7B0 ... 0xD7FF).contains(value)
        {
            bits |= 2
        }
        if properties.isEmojiPresentation { bits |= 4 }
        if properties.isEmoji { bits |= 8 }
        return bits
    }

    @Test func `every scalar's classes match the properties they were generated from`() {
        var mismatches: [UInt32] = []
        for value in UInt32(0) ... 0x10FFFF where UnicodeWidth.classes(of: value) != Self.expected(value) {
            mismatches.append(value)
            if mismatches.count == 10 { break }
        }
        #expect(mismatches.isEmpty, "regenerate the table: \(mismatches.map { String($0, radix: 16) })")
    }
}
