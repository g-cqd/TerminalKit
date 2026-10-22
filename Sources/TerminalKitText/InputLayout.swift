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

    public init(_ text: String, columns: Int, firstRowIndent: Int = 0, tabSize: Int = 4) {
        let columns = max(1, columns)
        self.columns = columns
        self.firstRowIndent = min(max(0, firstRowIndent), columns - 1)
        carets.reserveCapacity(text.count + 1)
        let tabSize = max(1, tabSize)
        var column = self.firstRowIndent
        // Before each character: `rows` holds everything rendered so far, `column` is its end, and every earlier source boundary
        // has one cell in `carets`. Rows and caret cells are monotonic in reading order.
        for character in text {
            if character.isNewline {
                let position =
                    column >= columns
                    ? Position(row: rows.count, column: 0) : Position(row: rows.count - 1, column: column)
                carets.append(position)
                rows.append("")
                column = 0
                continue
            }
            var shown = character
            if character != "\t", character.unicodeScalars.contains(where: TextSanitizer.isControl) { shown = "�" }
            let width = UnicodeWidth.displayWidth(of: shown)
            if width > columns { shown = "?" }
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
        if column >= columns {
            rows.append("")
            column = 0
        }
        carets.append(Position(row: rows.count - 1, column: column))
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
