import TerminalKitCodecs
public import TerminalKitStyle
import TerminalKitText

/// A flat grid of cells representing the terminal screen.
///
/// No cell the diff sends holds a control character: the setter, ``fill(row:col:width:height:cell:)`` and
/// ``write(_:row:col:style:)`` store a C0 control, DEL or a C1 control as ``replacement``, so text such as a file
/// name cannot reach the terminal as a command. A continuation cell keeps its character, which the diff never sends.
public struct ScreenBuffer: Sendable {
    /// The cells, 16 bytes each, in row-major order (row * columns + col) (ADR-0021).
    private(set) var packed: ContiguousArray<PackedCell>

    /// The last style written and its id in ``StyleTable``, so consecutive writes in one style take no lock.
    private var lastStyle = Style.default
    private var lastStyleID: UInt32 = 0

    /// Every cell in row-major order, decoded. Builds a new array on each call: for inspection and tests,
    /// not for a frame's work.
    public var cells: ContiguousArray<Cell> { ContiguousArray(packed.lazy.map(\.cell)) }

    /// The number of columns (horizontal cells) in the buffer.
    public let columns: Int

    /// The number of rows (vertical cells) in the buffer.
    public let rows: Int

    /// Tracks which cell indices have been modified since the last flush.
    public var dirty: DirtyTracker

    /// Creates a new buffer filled with empty cells.
    ///
    /// - Parameters:
    ///   - columns: The number of horizontal cells.
    ///   - rows: The number of vertical cells.
    public init(columns: Int, rows: Int) {
        let safeColumns = max(0, columns)
        let safeRows = max(0, rows)
        let (capacity, overflow) = safeColumns.multipliedReportingOverflow(by: safeRows)
        precondition(!overflow, "ScreenBuffer size overflows Int: columns=\(columns), rows=\(rows)")
        self.columns = safeColumns
        self.rows = safeRows
        self.packed = ContiguousArray<PackedCell>(repeating: .empty, count: capacity)
        self.dirty = DirtyTracker(capacity: capacity)
    }

    /// Accesses the cell at the given row and column.
    ///
    /// Out-of-bounds reads return `Cell.empty`; out-of-bounds writes are silently ignored. The setter stores a
    /// control character as ``replacement`` and marks the index dirty only when the stored cell changes.
    public subscript(row: Int, col: Int) -> Cell {
        get {
            guard row >= 0, row < rows, col >= 0, col < columns else { return .empty }
            return packed[row &* columns &+ col].cell
        }
        set {
            guard row >= 0, row < rows, col >= 0, col < columns else { return }
            let index = row &* columns &+ col
            var shown = newValue
            if Self.needsReplacement(newValue) { shown.character = Self.replacement }
            store(PackedCell(character: shown.character, width: shown.width, styleID: styleID(shown.style)), at: index)
        }
    }

    /// Writes a string with the given style into the buffer starting at the specified position.
    ///
    /// Wide characters (CJK, fullwidth) occupy two columns. A continuation cell is placed
    /// in the second column. Characters that would extend past the buffer edge are dropped, and a control character
    /// is written as ``replacement``.
    ///
    /// - Parameters:
    ///   - string: The text to write.
    ///   - row: The zero-based row index at which to begin writing.
    ///   - col: The zero-based column index at which to begin writing.
    ///   - style: The visual style to apply to every character in `string`.
    /// - Complexity: O(n) in the UTF-8 length of `string`; printable ASCII skips grapheme breaking and width lookup.
    public mutating func write(_ string: String, row: Int, col: Int, style: Style) {
        guard row >= 0, row < rows, col >= 0 else { return }
        let base = row &* columns
        let id = styleID(style)
        var c = col
        let text = string.utf8Span
        let bytes = text.span
        var characters = text.makeCharacterIterator()
        var offset = 0
        while offset < bytes.count {
            let byte = bytes[offset]
            let next = offset &+ 1
            // Printable ASCII followed by ASCII, or by nothing, is a one-column character of its own.
            if byte &- 0x20 < 0x5F, next == bytes.count || bytes[next] < 0x80 {
                guard c < columns else { return }
                storeNarrow(.ascii(byte, styleID: id), at: base, column: c)
                c &+= 1
                offset = next
                continue
            }
            if characters.currentCodeUnitOffset != offset {
                characters.reset(roundingForwardsFrom: offset)
            }
            guard let raw = characters.next() else { return }
            offset = characters.currentCodeUnitOffset
            let char = Self.isControl(raw) ? Self.replacement : raw
            let w = UnicodeWidth.displayWidth(of: char)
            guard w > 0 else { continue }
            if w == 2 {
                guard c + 1 < columns else { return }
                store(PackedCell(character: char, width: 2, styleID: id), at: base &+ c)
                store(PackedCell(character: "\0", width: 0, styleID: id), at: base &+ c &+ 1)
                c += 2
            } else {
                guard c < columns else { return }
                storeNarrow(PackedCell(character: char, width: 1, styleID: id), at: base, column: c)
                c += 1
            }
        }
    }

    /// The glyph a control character is shown as.
    public static let replacement: Character = "\u{FFFD}"

    /// Whether `character` carries a C0 control, DEL or a C1 control, per `TextSanitizer.isControl(_:)`.
    /// - Complexity: O(1) for ASCII, otherwise O(n) in the scalars of `character`.
    @inline(__always)
    public static func isControl(_ character: Character) -> Bool {
        // ASCII, the common case, is a single byte, so it needs no scalar decoding.
        let utf8 = character.utf8
        if utf8.count == 1, let byte = utf8.first {
            return TextSanitizer.isControl(Unicode.Scalar(byte))
        }
        return character.unicodeScalars.contains(where: TextSanitizer.isControl)
    }

    /// Whether storing `cell` as it is would send a control character: its character is one, and it is not a
    /// continuation cell, whose character the diff never sends.
    @inline(__always)
    static func needsReplacement(_ cell: Cell) -> Bool {
        cell.width != 0 && isControl(cell.character)
    }

    /// Stores `cell`, which holds no control character unless it is a continuation, and marks its index dirty when
    /// that changes the cell.
    @inline(__always)
    private mutating func store(_ cell: PackedCell, at index: Int) {
        guard packed[index] != cell else { return }
        packed[index] = cell
        dirty.mark(index)
    }

    /// The id of `style`, from the last write's when it is the same style.
    @inline(__always)
    private mutating func styleID(_ style: Style) -> UInt32 {
        if style == lastStyle { return lastStyleID }
        lastStyle = style
        lastStyleID = StyleTable.id(of: style)
        return lastStyleID
    }

    /// Stores a one-column `cell`, free of controls, at `column` of the row starting at `base`, and clears the
    /// continuation cell after it, which lost the wide character it belonged to.
    @inline(__always)
    private mutating func storeNarrow(_ cell: PackedCell, at base: Int, column: Int) {
        store(cell, at: base &+ column)
        let after = column &+ 1
        if after < columns, packed[base &+ after].isContinuation {
            store(.empty, at: base &+ after)
        }
    }

    /// Marks dirty every cell of `rows` that differs from `other`'s, which has the same dimensions: after a
    /// terminal scroll, the cells the scroll moved wrongly, such as a sidebar's, or the row it exposed.
    mutating func markDifferences(from other: ScreenBuffer, rows: Range<Int>) {
        let mine = packed.span
        let theirs = other.packed.span
        for index in rows.lowerBound &* columns ..< rows.upperBound &* columns where mine[index] != theirs[index] {
            dirty.mark(index)
        }
    }

    /// A hash of row `row`'s cells, for finding where rows moved between two frames. Equal rows hash equal;
    /// unequal rows rarely do, and a collision only costs bytes, since the diff still compares every cell.
    @inline(__always)
    func rowHash(_ row: Int) -> UInt64 {
        // Each cell is mixed on its own and the results are added, so no multiply waits for the one before it;
        // the column is mixed in so two cells that swap places change the hash.
        var hash: UInt64 = 0
        let base = row &* columns
        let cells = packed.span
        for col in 0 ..< columns {
            let cell = cells[base &+ col]
            hash &+= (cell.low ^ UInt64(col) &* 0x9E37_79B9_7F4A_7C15) &* 0xBF58_476D_1CE4_E5B9 ^ cell.high
        }
        return hash
    }

    /// Replaces every cell in the buffer with `Cell.empty`, marking changed cells dirty.
    public mutating func clear() {
        for i in packed.indices where packed[i] != .empty {
            packed[i] = .empty
            dirty.mark(i)
        }
    }

    /// Fills a rectangular region of the buffer with the given cell value.
    ///
    /// The region is clamped to the buffer bounds. Out-of-bounds or zero-area rectangles are ignored. A control
    /// character in `cell` is stored as ``replacement``.
    ///
    /// - Parameters:
    ///   - row: The zero-based row index of the top-left corner.
    ///   - col: The zero-based column index of the top-left corner.
    ///   - width: The number of columns to fill.
    ///   - height: The number of rows to fill.
    ///   - cell: The cell value to write into every position in the rectangle.
    public mutating func fill(row: Int, col: Int, width: Int, height: Int, cell: Cell) {
        guard row >= 0, row < rows, col >= 0, col < columns, width > 0, height > 0 else { return }
        var cleaned = cell
        if Self.needsReplacement(cleaned) {
            cleaned.character = Self.replacement
        }
        let shown = PackedCell(character: cleaned.character, width: cleaned.width, styleID: styleID(cleaned.style))
        let rowEnd = row + min(height, rows - row)
        let colEnd = col + min(width, columns - col)
        for r in row ..< rowEnd {
            let base = r &* columns
            for c in col ..< colEnd {
                store(shown, at: base &+ c)
            }
        }
    }

    /// Shifts rows within a rectangular region vertically by `delta` rows.
    ///
    /// Positive `delta` shifts content up (for scroll-down); negative shifts down (for scroll-up).
    /// Cells in the vacated rows are left unchanged — the caller's renderer will overwrite them.
    /// No dirty bits are set by the shift itself; the subsequent render marks only cells that
    /// differ from the shifted content.
    ///
    /// - Parameters:
    ///   - regionY: The top row of the region.
    ///   - regionHeight: The number of rows in the region.
    ///   - regionX: The left column of the region.
    ///   - regionWidth: The number of columns in the region.
    ///   - delta: Number of rows to shift (positive = up, negative = down).
    public mutating func shiftRows(
        regionY: Int, regionHeight: Int,
        regionX: Int, regionWidth: Int,
        delta: Int
    ) {
        guard delta != 0, regionWidth > 0, regionHeight > 0, abs(delta) < regionHeight,
            regionY >= 0, regionX >= 0, regionY + regionHeight <= rows, regionX + regionWidth <= columns
        else {
            return
        }

        // Through a span: indexing the array would check its uniqueness on every store.
        let columns = columns
        var cells = packed.mutableSpan
        if delta > 0 {
            // Scroll down: content moves up
            for row in regionY ..< (regionY + regionHeight - delta) {
                let dstBase = row &* columns
                let srcBase = (row &+ delta) &* columns
                for col in regionX ..< (regionX + regionWidth) {
                    cells[dstBase &+ col] = cells[srcBase &+ col]
                }
            }
        } else {
            let absDelta = -delta
            for row in stride(from: regionY + regionHeight - 1, through: regionY + absDelta, by: -1) {
                let dstBase = row &* columns
                let srcBase = (row &- absDelta) &* columns
                for col in regionX ..< (regionX + regionWidth) {
                    cells[dstBase &+ col] = cells[srcBase &+ col]
                }
            }
        }
    }

    /// Copies cells marked dirty in `source` into this buffer without sharing either grid's storage.
    /// - Precondition: Both buffers have the same dimensions.
    /// - Complexity: O(columns × rows / 64 + dirty cells) time, walking the dirty bits a word at a time; O(1) extra
    ///   space with unique storage, otherwise O(columns × rows).
    mutating func adoptDirtyCells(from source: ScreenBuffer) {
        precondition(columns == source.columns && rows == source.rows, "ScreenBuffer dimensions differ")
        let sourceCells = source.packed.span
        var destination = packed.mutableSpan
        source.dirty.forEachDirtyIndex { index in destination[index] = sourceCells[index] }
    }

    /// Copies every cell after a forced redraw without sharing either grid's storage.
    /// - Precondition: Both buffers have the same dimensions.
    /// - Complexity: O(columns × rows) time; O(1) extra space with unique storage, otherwise O(columns × rows).
    mutating func adoptAllCells(from source: ScreenBuffer) {
        precondition(columns == source.columns && rows == source.rows, "ScreenBuffer dimensions differ")
        let sourceCells = source.packed.span
        var destination = packed.mutableSpan
        for index in 0 ..< destination.count {
            destination[index] = sourceCells[index]
        }
    }

    /// Resizes the buffer to the new dimensions, preserving the overlapping content.
    ///
    /// Cells within the intersection of the old and new dimensions are copied over.
    /// All cells in the new buffer are marked dirty so the next flush redraws the full viewport.
    ///
    /// - Parameters:
    ///   - newCols: The new number of columns.
    ///   - newRows: The new number of rows.
    public mutating func resize(columns newCols: Int, rows newRows: Int) {
        let safeCols = max(0, newCols)
        let safeRows = max(0, newRows)
        let (capacity, overflow) = safeCols.multipliedReportingOverflow(by: safeRows)
        precondition(!overflow, "ScreenBuffer resize overflows Int: cols=\(newCols), rows=\(newRows)")
        var newCells = ContiguousArray<PackedCell>(repeating: .empty, count: capacity)
        let copyRows = min(rows, safeRows)
        let copyCols = min(columns, safeCols)
        for r in 0 ..< copyRows {
            for c in 0 ..< copyCols {
                newCells[r * safeCols + c] = packed[r * columns + c]
            }
        }
        self = ScreenBuffer._fromParts(cells: newCells, columns: safeCols, rows: safeRows)
    }

    private static func _fromParts(cells: ContiguousArray<PackedCell>, columns: Int, rows: Int)
        -> ScreenBuffer
    {
        var buf = ScreenBuffer(columns: columns, rows: rows)
        buf.packed = cells
        // Mark everything dirty after resize (batch operation, O(words) not O(cells))
        buf.dirty.markAll()
        return buf
    }
}
