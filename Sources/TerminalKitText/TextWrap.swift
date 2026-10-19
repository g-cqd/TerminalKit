/// Wraps text to a display width: at spaces when a line has one, inside a word only when the word alone is too
/// wide. Widths are display columns (`UnicodeWidth`), so wide characters count as two.
///
/// The walk is over UTF-8 bytes: an ASCII byte followed by an ASCII byte (or the end) is a grapheme of its own,
/// one column wide, and needs no grapheme segmentation; anything else is segmented from where it starts. Lines
/// are cut at grapheme boundaries and built once, from byte ranges. For prose that is ASCII but for a few
/// characters, nearly all of it takes the fast path (roadmap 0012).
public enum TextWrap {
    /// The lines of `text` no wider than `width`. Line feeds end lines; tabs become four spaces.
    public static func lines(_ text: String, width: Int) -> [String] {
        let width = Swift.max(1, width)
        if text.utf8.contains(0x09) { return lines(text.replacing("\t", with: "    "), width: width) }
        let utf8 = text.utf8Span
        let bytes = utf8.span
        var characters = utf8.makeCharacterIterator()
        var lines: [String] = []
        var lineStart = 0
        var lineWidth = 0
        // The last space on the line: where it is, and the width before it. A space at the line's start is no break.
        var lastSpace: (offset: Int, width: Int)?
        var offset = 0

        func line(_ range: Range<Int>) -> String {
            String(unsafeUninitializedCapacity: range.count) { buffer in
                // SAFETY: `range` lies within `bytes` (offsets this walk produced) and `buffer` holds `range.count`.
                bytes.withUnsafeBufferPointer { source in
                    unsafe buffer.baseAddress?.update(from: source.baseAddress! + range.lowerBound, count: range.count)
                }
                return range.count
            }
        }

        while offset < bytes.count {
            let byte = bytes[offset]
            let next: Int
            let characterWidth: Int
            let isSpace: Bool
            if byte < 0x80, byte != 0x0D, offset &+ 1 == bytes.count || bytes[offset &+ 1] < 0x80 {
                if byte == 0x0A {
                    lines.append(line(lineStart ..< offset))
                    (lineStart, lineWidth, lastSpace) = (offset &+ 1, 0, nil)
                    offset &+= 1
                    continue
                }
                next = offset &+ 1
                characterWidth = byte == 0 ? 0 : 1
                isSpace = byte == 0x20
            } else {
                if characters.currentCodeUnitOffset != offset { characters.reset(roundingForwardsFrom: offset) }
                guard let character = characters.next() else { break }
                next = characters.currentCodeUnitOffset
                if character == "\n" {
                    lines.append(line(lineStart ..< offset))
                    (lineStart, lineWidth, lastSpace) = (next, 0, nil)
                    offset = next
                    continue
                }
                characterWidth = UnicodeWidth.displayWidth(of: character)
                isSpace = character == " "
            }
            if lineWidth &+ characterWidth > width {
                if isSpace {
                    // The line is exactly full: break here, and the space is the break.
                    lines.append(line(lineStart ..< offset))
                    (lineStart, lineWidth, lastSpace) = (next, 0, nil)
                    offset = next
                    continue
                }
                if let space = lastSpace, space.offset > lineStart {
                    // Break at the last space: the space itself is dropped, the rest carries over.
                    lines.append(line(lineStart ..< space.offset))
                    lineStart = space.offset &+ 1
                    lineWidth = lineWidth &- space.width &- 1
                } else {
                    lines.append(line(lineStart ..< offset))
                    lineStart = offset
                    lineWidth = 0
                }
                lastSpace = nil
            }
            if isSpace { lastSpace = (offset, lineWidth) }
            lineWidth &+= characterWidth
            offset = next
        }
        lines.append(line(lineStart ..< bytes.count))
        return lines
    }
}
