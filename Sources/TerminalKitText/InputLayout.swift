/// Hard-wrapped editable text, indexed by source `Character` offsets and terminal display cells (roadmap 0019).
///
/// Newlines end rows; tabs expand to tab stops. Controls display as U+FFFD, and a grapheme wider than the entire viewport displays
/// as `?`, without changing source offsets. The host supplies any first-row prefix separately.
///
/// A soft-wrap boundary belongs to the next row. An exactly full input ends with an empty cursor row. Before a hard newline at
/// the right edge, the caret shares the following row's first cell instead of inventing a blank row or entering a wide continuation.
/// - Complexity: Building is O(b + e), for b source UTF-8 bytes and e rendered bytes, with O(n + e) storage for n source graphemes.
public struct InputLayout: Sendable {
    /// A zero-based display row and column. Columns name cells, not bytes or graphemes.
    public struct Position: Sendable, Equatable {
        public var row: Int
        public var column: Int

        public init(row: Int, column: Int) {
            self.row = row
            self.column = column
        }
    }

    /// The text of each display row, without the first-row prefix the host supplies.
    public private(set) var rows = [""]
    public let columns: Int
    /// Cells reserved before the first source character. Clamped to leave one editable cell.
    public let firstRowIndent: Int
    private var carets: [Position] = []

    /// `wrapsWords` breaks before a word following whitespace when it fits a whole row but not the remaining cells, less one kept
    /// for the space after it.
    /// Whitespace is retained, not trimmed or inserted; the default keeps hard wrapping for existing consumers.
    public init(_ text: String, columns: Int, firstRowIndent: Int = 0, tabSize: Int = 4, wrapsWords: Bool = false) {
        let columns = max(1, columns)
        self.columns = columns
        self.firstRowIndent = min(max(0, firstRowIndent), columns - 1)
        carets.reserveCapacity(text.utf8.count + 1)
        let tabSize = max(1, tabSize)
        var column = self.firstRowIndent
        // Before each step: `rows` holds everything rendered so far, `column` is its end, and every earlier source boundary has one
        // cell in `carets`. Rows and caret cells are monotonic in reading order. Runs of printable ASCII, most of any draft, are laid
        // out a row's worth at a time (ask roadmap 0151); everything else one grapheme at a time.
        if wrapsWords {
            placeWords(text, column: &column, tabSize: tabSize)
            if column >= columns {
                rows.append("")
                column = 0
            }
            carets.append(Position(row: rows.count - 1, column: column))
            return
        }
        let utf8 = text.utf8
        var index = text.startIndex
        while index < text.endIndex {
            let runEnd = Self.asciiRunEnd(in: utf8, from: index)
            if runEnd > index {
                place(ascii: utf8[index ..< runEnd], column: &column)
                index = runEnd
                continue
            }
            let next = text.index(after: index)
            place(text[index], column: &column, tabSize: tabSize)
            index = next
        }
        if column >= columns {
            rows.append("")
            column = 0
        }
        carets.append(Position(row: rows.count - 1, column: column))
    }

    /// The cells a word `width` wide asks of a row: its own and one for the space after it, when the row can hold both. A word that
    /// ended in the last cell sent its space to the start of the next row, and typing that space moved the cursor down; keeping the
    /// cell whether or not the space is there yet means a word never moves when the space is typed.
    private static func cells(for width: Int, of columns: Int) -> Int { Swift.min(width + 1, columns) }

    /// Word-aware layout shares the same caret placement, keeping every space in the source. A word that fits a full row
    /// moves whole after a separator; a longer word or the first word after a prefix keeps the hard-wrap fallback.
    private mutating func placeWords(_ text: String, column: inout Int, tabSize: Int) {
        var start = text.startIndex
        var afterSeparator = false
        let bytes = text.utf8
        while start < text.endIndex {
            // ASCII words ending at ASCII whitespace are whole graphemes. Scan their bytes, not each Character.
            var asciiEnd = start
            while asciiEnd < bytes.endIndex, (0x21 ... 0x7E).contains(bytes[asciiEnd]) {
                asciiEnd = bytes.index(after: asciiEnd)
            }
            if asciiEnd > start,
                asciiEnd == bytes.endIndex || [0x20, 0x09, 0x0A, 0x0D, 0x0B, 0x0C].contains(bytes[asciiEnd])
            {
                let word = bytes[start ..< asciiEnd]
                let width = word.count
                if afterSeparator, column > 0, width <= columns, Self.cells(for: width, of: columns) > columns - column
                {
                    rows.append("")
                    column = 0
                }
                place(ascii: word, column: &column)
                start = asciiEnd
                afterSeparator = false
                continue
            }
            let character = text[start]
            if character.isWhitespace {
                place(character, column: &column, tabSize: tabSize)
                afterSeparator = !character.isNewline
                start = text.index(after: start)
                continue
            }
            var end = text.index(after: start)
            while end < text.endIndex, !text[end].isWhitespace { end = text.index(after: end) }
            let word = text[start ..< end]
            let ascii = word.utf8.allSatisfy { (0x21 ... 0x7E).contains($0) }
            let width = ascii ? word.utf8.count : UnicodeWidth.displayWidth(of: String(word))
            if afterSeparator, column > 0, width <= columns, Self.cells(for: width, of: columns) > columns - column {
                rows.append("")
                column = 0
            }
            // Printable ASCII words keep the row-at-a-time fast path; other words use the same grapheme placement as hard wrap.
            if ascii {
                place(ascii: word.utf8, column: &column)
            } else {
                for character in word { place(character, column: &column, tabSize: tabSize) }
            }
            afterSeparator = false
            start = end
        }
    }

    /// Where the run of printable ASCII that starts at `start` ends: each byte of it is a grapheme of its own, one cell wide. The last
    /// byte before a non-ASCII one is left out, since the scalars after it (a combining mark, a joiner) can join its grapheme.
    private static func asciiRunEnd(in utf8: String.UTF8View, from start: String.Index) -> String.Index {
        var end = start
        while end < utf8.endIndex, (0x20 ... 0x7E).contains(utf8[end]) { end = utf8.index(after: end) }
        guard end > start, end < utf8.endIndex, utf8[end] >= 0x80 else { return end }
        return utf8.index(before: end)
    }

    /// Lays out a run of printable ASCII, a row's worth at a time.
    private mutating func place(ascii run: Substring.UTF8View, column: inout Int) {
        var start = run.startIndex
        var remaining = run.count
        while remaining > 0 {
            if column >= columns {
                rows.append("")
                column = 0
            }
            let take = min(columns - column, remaining)
            let end = run.index(start, offsetBy: take)
            let row = rows.count - 1
            for cell in column ..< column + take { carets.append(Position(row: row, column: cell)) }
            rows[row] += Substring(run[start ..< end])
            column += take
            remaining -= take
            start = end
        }
    }

    /// Lays out one grapheme: a newline ends the row; a tab runs to the next stop; a control shows as U+FFFD and a grapheme wider than
    /// the viewport as `?`.
    private mutating func place(_ character: Character, column: inout Int, tabSize: Int) {
        if character.isNewline {
            let position =
                column >= columns
                ? Position(row: rows.count, column: 0) : Position(row: rows.count - 1, column: column)
            carets.append(position)
            rows.append("")
            column = 0
            return
        }
        var shown = character
        if character != "\t", character.unicodeScalars.contains(where: TextSanitizer.isControl) { shown = "�" }
        let width = UnicodeWidth.displayWidth(of: shown)
        if width > columns { shown = "?" }
        let columns = columns
        func measured(at column: Int) -> Int {
            character == "\t" ? min(tabSize - column % tabSize, columns) : min(width, columns)
        }
        if column >= columns || measured(at: column) > columns - column {
            rows.append("")
            column = 0
        }
        carets.append(Position(row: rows.count - 1, column: column))
        let used = measured(at: column)
        if character == "\t" {
            rows[rows.count - 1] += String(repeating: " ", count: used)
        } else {
            rows[rows.count - 1].append(shown)
        }
        column += used
    }

    /// The display cell for a source grapheme boundary; out-of-range offsets clamp to the text.
    /// - Complexity: O(1).
    public func position(at offset: Int) -> Position {
        carets[min(max(0, offset), carets.count - 1)]
    }

    /// The caret on `row` at or before `column`, clamped to that row's addressable caret cells.
    /// A prefix-only row with no source caret maps to the first editable row. A cell inside a wide grapheme maps before it.
    /// - Complexity: O(log n), for n source graphemes. Equal cells, from zero-width characters, choose the last boundary.
    public func offset(atRow row: Int, column: Int) -> Int {
        let row = min(max(0, row), rows.count - 1)
        let column = max(0, column)
        var low = 0
        var high = carets.count
        // Upper bound of the requested cell: every caret before `low` is <= it, every one at or after `high` is > it.
        while low < high {
            let middle = low + (high - low) / 2
            let position = carets[middle]
            if position.row < row || (position.row == row && position.column <= column) {
                low = middle + 1
            } else {
                high = middle
            }
        }
        if low > 0, carets[low - 1].row == row { return low - 1 }
        return min(low, carets.count - 1)
    }
}
