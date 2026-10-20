/// Wraps text to a display width: at spaces when a line has one, inside a word only when the word alone is too
/// wide. Widths are display columns (`UnicodeWidth`), so wide characters count as two.
///
/// The walk is over UTF-8 bytes: an ASCII byte followed by an ASCII byte (or the end) is a grapheme of its own,
/// one column wide, and needs no grapheme segmentation; anything else is segmented from where it starts. Lines
/// are cut at grapheme boundaries and built once, from byte ranges. For prose that is ASCII but for a few
/// characters, nearly all of it takes the fast path (roadmap 0012).
public enum TextWrap {
    /// One row of wrapped text and where it came from, so a place on the screen can be mapped back to the text (roadmap 0017).
    public struct Row: Sendable, Equatable {
        /// The row's text, exactly what ``lines(_:width:)`` returns for it.
        public var text: String
        /// The hard line it belongs to, counted from zero: a line feed ends one, and a line that wraps is several rows.
        public var line: Int
        /// The grapheme offset, within that hard line, of the row's first grapheme. A space at a break is dropped, so the next row
        /// starts one past it.
        public var offset: Int
    }

    /// The lines of `text` no wider than `width`. Line feeds end lines; tabs become four spaces.
    public static func lines(_ text: String, width: Int) -> [String] {
        var lines: [String] = []
        walk(text, width: width) { row, _, _ in lines.append(row) }
        return lines
    }

    /// The same rows as ``lines(_:width:)``, each with its hard line and grapheme offset.
    ///
    /// Offsets count `Character`s of the text **as wrapped**, after tabs became four spaces, so the content a selection reads must be
    /// that text too. Each row's text is a contiguous run of its hard line's graphemes starting at `offset`.
    public static func rows(_ text: String, width: Int) -> [Row] {
        var rows: [Row] = []
        walk(text, width: width) { row, line, offset in rows.append(Row(text: row, line: line, offset: offset)) }
        return rows
    }

    /// The one walk both entry points share, so they cannot disagree: calls `emit` with each row, its hard line, and the grapheme
    /// offset of its first grapheme in that line.
    private static func walk(_ text: String, width: Int, emit: (String, Int, Int) -> Void) {
        let width = Swift.max(1, width)
        if text.utf8.contains(0x09) { return walk(text.replacing("\t", with: "    "), width: width, emit: emit) }
        let utf8 = text.utf8Span
        let bytes = utf8.span
        var characters = utf8.makeCharacterIterator()
        var lineStart = 0
        var lineWidth = 0
        // The last space on the line: where it is, the width before it, and its grapheme index in the hard line.
        // A space at the line's start is no break.
        var lastSpace: (offset: Int, width: Int, character: Int)?
        var offset = 0
        // Which hard line, the grapheme index of the grapheme at `offset` within it, and that of the row's first grapheme.
        var hardLine = 0
        var character = 0
        var lineStartCharacter = 0

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
                    emit(line(lineStart ..< offset), hardLine, lineStartCharacter)
                    (lineStart, lineWidth, lastSpace) = (offset &+ 1, 0, nil)
                    (hardLine, character, lineStartCharacter) = (hardLine &+ 1, 0, 0)
                    offset &+= 1
                    continue
                }
                next = offset &+ 1
                characterWidth = byte == 0 ? 0 : 1
                isSpace = byte == 0x20
            } else {
                if characters.currentCodeUnitOffset != offset { characters.reset(roundingForwardsFrom: offset) }
                guard let grapheme = characters.next() else { break }
                next = characters.currentCodeUnitOffset
                if grapheme == "\n" {
                    emit(line(lineStart ..< offset), hardLine, lineStartCharacter)
                    (lineStart, lineWidth, lastSpace) = (next, 0, nil)
                    (hardLine, character, lineStartCharacter) = (hardLine &+ 1, 0, 0)
                    offset = next
                    continue
                }
                characterWidth = UnicodeWidth.displayWidth(of: grapheme)
                isSpace = grapheme == " "
            }
            if lineWidth &+ characterWidth > width {
                if isSpace {
                    // The line is exactly full: break here, and the space is the break.
                    emit(line(lineStart ..< offset), hardLine, lineStartCharacter)
                    (lineStart, lineWidth, lastSpace) = (next, 0, nil)
                    lineStartCharacter = character &+ 1
                    character &+= 1
                    offset = next
                    continue
                }
                if let space = lastSpace, space.offset > lineStart {
                    // Break at the last space: the space itself is dropped, the rest carries over.
                    emit(line(lineStart ..< space.offset), hardLine, lineStartCharacter)
                    lineStart = space.offset &+ 1
                    lineStartCharacter = space.character &+ 1
                    lineWidth = lineWidth &- space.width &- 1
                } else {
                    emit(line(lineStart ..< offset), hardLine, lineStartCharacter)
                    lineStart = offset
                    lineStartCharacter = character
                    lineWidth = 0
                }
                lastSpace = nil
            }
            if isSpace { lastSpace = (offset, lineWidth, character) }
            lineWidth &+= characterWidth
            offset = next
            character &+= 1
        }
        emit(line(lineStart ..< bytes.count), hardLine, lineStartCharacter)
    }
}
