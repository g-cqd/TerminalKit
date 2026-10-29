internal import TerminalKitText

/// Wraps a block's pieces to a width, across their styles: at spaces when a row has one, inside a word only when the word alone is too wide,
/// as `TextWrap` does for plain text; or at any grapheme, for code. A space at a break is dropped.
struct RowWrap {
    /// A grapheme of a piece: its bytes in the piece, its columns, and whether it is a space. A line break has piece index -1.
    struct Glyph {
        var piece: Int32
        var start: Int32
        var end: Int32
        var width: Int16
        var isSpace: Bool
    }

    let pieces: [Piece]
    let glyphs: [Glyph]

    /// The graphemes of `pieces`. A grapheme with a control character in it is not drawn: a terminal could read it as a command.
    init(_ pieces: [Piece]) {
        self.pieces = pieces
        var glyphs: [Glyph] = []
        glyphs.reserveCapacity(pieces.reduce(0) { $0 + $1.text.utf8.count })
        for (index, piece) in pieces.enumerated() {
            if piece.isBreak {
                glyphs.append(Glyph(piece: -1, start: 0, end: 0, width: 0, isSpace: false))
                continue
            }
            var offset = 0
            for character in piece.text {
                let count = character.utf8.count
                defer { offset += count }
                if character.unicodeScalars.contains(where: TextSanitizer.isControl) { continue }
                let width = character.isASCII ? 1 : UnicodeWidth.displayWidth(of: character)
                glyphs.append(
                    Glyph(
                        piece: Int32(index), start: Int32(offset), end: Int32(offset + count), width: Int16(width),
                        isSpace: character == " "))
            }
        }
        self.glyphs = glyphs
    }

    /// The widest hard line, and the widest word: what a table column needs to show a cell on one row, and at the least.
    var measure: (natural: Int, longestWord: Int) {
        var natural = 0
        var word = 0
        var line = 0
        var current = 0
        for glyph in glyphs {
            if glyph.piece < 0 {
                (natural, line, current) = (Swift.max(natural, line), 0, 0)
                continue
            }
            line += Int(glyph.width)
            current = glyph.isSpace ? 0 : current + Int(glyph.width)
            word = Swift.max(word, current)
        }
        return (Swift.max(natural, line), word)
    }

    /// The rows of the pieces no wider than `width`, at least one. A grapheme wider than `width` gets a row of its own and is wider.
    func rows(width: Int, breaksAnywhere: Bool = false) -> [[StyledRun]] {
        let width = Swift.max(1, width)
        var rows: [[StyledRun]] = []
        var start = 0
        var lineWidth = 0
        // The last space on the row, and the row's width once it is included.
        var lastSpace: (index: Int, widthAfter: Int)?
        // Whether the last row ended at a space that did not fit: a row closed that way leaves no empty row after it.
        var brokeAtSpace = false
        for (index, glyph) in glyphs.enumerated() {
            if glyph.piece < 0 {
                rows.append(runs(start ..< index))
                (start, lineWidth, lastSpace, brokeAtSpace) = (index + 1, 0, nil, false)
                continue
            }
            brokeAtSpace = false
            let columns = Int(glyph.width)
            if lineWidth + columns > width {
                if glyph.isSpace, !breaksAnywhere {
                    rows.append(runs(start ..< index))
                    (start, lineWidth, lastSpace, brokeAtSpace) = (index + 1, 0, nil, true)
                    continue
                }
                if let space = lastSpace, space.index > start {
                    rows.append(runs(start ..< space.index))
                    start = space.index + 1
                    lineWidth -= space.widthAfter
                }
                if lineWidth + columns > width, index > start {
                    rows.append(runs(start ..< index))
                    (start, lineWidth) = (index, 0)
                }
                lastSpace = nil
            }
            lineWidth += columns
            if glyph.isSpace, !breaksAnywhere { lastSpace = (index, lineWidth) }
        }
        if !brokeAtSpace || start < glyphs.count { rows.append(runs(start ..< glyphs.count)) }
        return rows
    }

    /// The runs of `range` of the glyphs: one per stretch of a piece's contiguous bytes.
    private func runs(_ range: Range<Int>) -> [StyledRun] {
        var runs: [StyledRun] = []
        var index = range.lowerBound
        while index < range.upperBound {
            let first = glyphs[index]
            var end = index + 1
            while end < range.upperBound, glyphs[end].piece == first.piece, glyphs[end].start == glyphs[end - 1].end {
                end += 1
            }
            runs.append(pieces[Int(first.piece)].run(Int(first.start) ..< Int(glyphs[end - 1].end)))
            index = end
        }
        return runs
    }

    /// `runs` with their first columns cut until at most `columns` are left: a prefix too wide for the row keeps its innermost part.
    static func keepingLast(_ columns: Int, of runs: [StyledRun]) -> [StyledRun] {
        var total = runs.reduce(0) { $0 + UnicodeWidth.displayWidth(of: $1.text) }
        guard total > columns else { return runs }
        var kept = runs
        while total > columns, !kept.isEmpty {
            guard let first = kept[0].text.first else {
                kept.removeFirst()
                continue
            }
            total -= UnicodeWidth.displayWidth(of: first)
            kept[0].text.removeFirst()
            if kept[0].text.isEmpty { kept.removeFirst() }
        }
        return kept
    }
}
