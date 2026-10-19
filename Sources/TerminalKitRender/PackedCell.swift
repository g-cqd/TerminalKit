import TerminalKitStyle
import TerminalKitText

/// A cell as the screen buffers store it: 16 bytes, compared as two integers (roadmap 0007, ADR-0021).
///
/// `Cell` holds a `Character` (16 bytes) and a `Style` (18), 40 bytes with padding, and comparing two of them
/// compares a grapheme and three colours. This holds the same information as:
/// - `low`: the grapheme's UTF-8 bytes, little-endian, when they fit in eight; otherwise its index in
///   ``GraphemeTable``;
/// - `high`: byte 0, the UTF-8 length, or ``overflowFlag`` for a table index; byte 1, the width; bytes 4–7,
///   the style's id in ``StyleTable``.
///
/// Measured over 189 million graphemes of agent transcripts, all but 7 fit in eight bytes (diary 2026-10-19-06).
struct PackedCell: Sendable, Equatable, BitwiseCopyable {
    var low: UInt64
    var high: UInt64

    /// The marker in the length byte for a grapheme kept in ``GraphemeTable``.
    static let overflowFlag: UInt64 = 0x80
    /// A bit in the length byte: terminals disagree on this grapheme's width (``UnicodeWidth/isContested(_:)``),
    /// so the diff places the next cell with a cursor move.
    static let contestedFlag: UInt64 = 0x40
    /// The bits of the length byte that hold the length.
    static let lengthMask: UInt64 = 0x3F

    @inline(__always)
    init(low: UInt64, high: UInt64) {
        self.low = low
        self.high = high
    }

    /// `Cell.empty`: a space, one column wide, in the default style.
    static let empty = PackedCell(low: 0x20, high: 1 | 1 << 8)

    /// A printable ASCII byte, one column wide.
    @inline(__always)
    static func ascii(_ byte: UInt8, styleID: UInt32) -> PackedCell {
        PackedCell(low: UInt64(byte), high: 1 | 1 << 8 | UInt64(styleID) << 32)
    }

    /// `character`, `width` columns wide, in the style with id `styleID`.
    init(character: Character, width: UInt8, styleID: UInt32) {
        let utf8 = character.utf8
        var low: UInt64 = 0
        var length: UInt64
        // ASCII is never contested; anything else is asked.
        let contested = utf8.count > 1 && UnicodeWidth.isContested(character)
        if utf8.count <= 8 {
            var shift: UInt64 = 0
            for byte in utf8 {
                low |= UInt64(byte) << shift
                shift &+= 8
            }
            length = UInt64(utf8.count)
        } else {
            low = UInt64(GraphemeTable.id(of: character))
            length = Self.overflowFlag
        }
        if contested { length |= Self.contestedFlag }
        self.init(low: low, high: length | UInt64(width) << 8 | UInt64(styleID) << 32)
    }

    /// Whether terminals disagree on this cell's width, so the cell after it needs a cursor move.
    @inline(__always)
    var isContested: Bool { high & Self.contestedFlag != 0 }

    /// `cell`, packed.
    init(_ cell: Cell) {
        self.init(character: cell.character, width: cell.width, styleID: StyleTable.id(of: cell.style))
    }

    /// The columns the cell covers: 0 for the continuation of a wide character, 1 or 2 otherwise.
    @inline(__always)
    var width: UInt8 { UInt8(truncatingIfNeeded: high >> 8) }

    /// Whether the cell continues the wide character before it.
    @inline(__always)
    var isContinuation: Bool { width == 0 }

    /// The style's id in ``StyleTable``.
    @inline(__always)
    var styleID: UInt32 { UInt32(truncatingIfNeeded: high >> 32) }

    /// The grapheme's UTF-8 length when it is stored inline, or nil for one kept in ``GraphemeTable``.
    @inline(__always)
    var inlineLength: Int? {
        high & Self.overflowFlag != 0 ? nil : Int(high & Self.lengthMask)
    }

    /// Appends the grapheme's UTF-8 bytes.
    @inline(__always)
    func appendUTF8(to bytes: inout ContiguousArray<UInt8>) {
        if high & Self.overflowFlag != 0 {
            bytes.append(contentsOf: GraphemeTable.character(UInt32(truncatingIfNeeded: low)).utf8)
            return
        }
        var remaining = low
        for _ in 0 ..< high & Self.lengthMask {
            bytes.append(UInt8(truncatingIfNeeded: remaining))
            remaining >>= 8
        }
    }

    /// The grapheme, decoded.
    var character: Character {
        let length = high & Self.lengthMask
        if high & Self.overflowFlag != 0 { return GraphemeTable.character(UInt32(truncatingIfNeeded: low)) }
        // SAFETY: the eight bytes of a local value, of which the first `length` (at most eight) are read.
        let string = withUnsafeBytes(of: low.littleEndian) { raw in
            unsafe String(decoding: raw.prefix(Int(length)), as: UTF8.self)
        }
        return string.first ?? " "
    }

    /// The cell as the public value type.
    var cell: Cell {
        Cell(character: character, style: StyleTable.style(styleID), width: width)
    }
}
