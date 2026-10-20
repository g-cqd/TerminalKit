/// Where one drawn row came from: the block and line it shows, which graphemes of it, and the cell it starts at.
///
/// This is the provenance a selection needs (TerminalKit roadmap 0017). The layout layer knows it, since it is what split a line
/// into rows; the host records it as it draws, one per row.
public struct RowProvenance<BlockID: Hashable & Sendable>: Sendable, Equatable {
    public var block: BlockID
    /// The block's index in reading order at the time of the frame, so rows can be ordered without asking the content.
    public var ordinal: Int
    /// The hard line of the block this row shows. A line that wraps is several rows with one `line`.
    public var line: Int
    /// The grapheme offset in that line of the first grapheme drawn on this row.
    public var firstOffset: Int
    /// The cell column where that first grapheme is drawn, zero-based.
    public var col: Int
    /// What was drawn on this row from the line: only its graphemes, not any padding or hint beside them.
    public var text: String

    public init(block: BlockID, ordinal: Int, line: Int, firstOffset: Int, col: Int, text: String) {
        self.block = block
        self.ordinal = ordinal
        self.line = line
        self.firstOffset = firstOffset
        self.col = col
        self.text = text
    }
}

/// Which side of the grapheme under the pointer a position falls on.
public enum SelectionEdge: Sendable, Equatable {
    /// Before it: where a selection starts.
    case leading
    /// After it: where a forward drag ends, so the grapheme under the pointer is included.
    case trailing
}

/// A position in content together with its block's index at the time of the frame.
public struct LocatedPosition<BlockID: Hashable & Sendable>: Sendable, Equatable {
    public var position: ContentPosition<BlockID>
    public var ordinal: Int

    public init(position: ContentPosition<BlockID>, ordinal: Int) {
        self.position = position
        self.ordinal = ordinal
    }
}

/// A run of cells to paint as selected: one row, from `startCol` up to and not including `endCol`.
public struct HighlightSpan: Sendable, Equatable {
    public var row: Int
    public var startCol: Int
    public var endCol: Int

    public init(row: Int, startCol: Int, endCol: Int) {
        self.row = row
        self.startCol = startCol
        self.endCol = endCol
    }
}

/// What every visible row of the screen shows, kept for one frame, so a cell can be turned back into a place in the content.
///
/// A row with no provenance (padding, a separator) holds no content. The host resets the map each frame and sets the rows it drew.
public struct RowMap<BlockID: Hashable & Sendable>: Sendable {
    private var rows: [RowProvenance<BlockID>?] = []

    public init() {}

    /// Forgets every row and sizes the map to a screen of `rowCount` rows, keeping the storage.
    public mutating func reset(rowCount: Int) {
        rows.removeAll(keepingCapacity: true)
        rows.append(contentsOf: repeatElement(nil, count: max(0, rowCount)))
    }

    public mutating func set(row: Int, to provenance: RowProvenance<BlockID>) {
        guard rows.indices.contains(row) else { return }
        rows[row] = provenance
    }

    public func provenance(atRow row: Int) -> RowProvenance<BlockID>? {
        rows.indices.contains(row) ? rows[row] : nil
    }

    /// The place in the content under a cell, or nil over a row that holds none.
    ///
    /// A column to the left of the text is the start of the row, and one past its end is the end. Wide graphemes and tabs are
    /// measured with ``TextDisplayMetrics``, so the column the mouse reports and the grapheme it lands on agree.
    public func position(row: Int, col: Int, edge: SelectionEdge = .leading, tabSize: Int = 4) -> LocatedPosition<
        BlockID
    >? {
        guard let source = provenance(atRow: row) else { return nil }
        let relative = col - source.col
        var offset = 0
        if relative > 0 {
            let characters = source.text.count
            let under = TextDisplayMetrics.characterOffset(
                forDisplayColumn: relative, in: source.text, tabSize: tabSize)
            offset = edge == .trailing && under < characters ? under + 1 : under
        }
        let position = ContentPosition(block: source.block, line: source.line, offset: source.firstOffset + offset)
        return LocatedPosition(position: position, ordinal: source.ordinal)
    }

    /// Like ``position(row:col:edge:tabSize:)``, but a cell over no content snaps to the nearest row that has some: the end of one
    /// above the pointer, or the start of one below it. The nearer wins, and below wins a tie. It is what a drag needs when the
    /// pointer crosses padding or leaves the content.
    public func nearestPosition(row: Int, col: Int, edge: SelectionEdge = .leading, tabSize: Int = 4)
        -> LocatedPosition<BlockID>?
    {
        if let exact = position(row: row, col: col, edge: edge, tabSize: tabSize) { return exact }
        var distance = 1
        while distance <= rows.count {
            if let below = provenance(atRow: row + distance) {
                let position = ContentPosition(block: below.block, line: below.line, offset: below.firstOffset)
                return LocatedPosition(position: position, ordinal: below.ordinal)
            }
            if let above = provenance(atRow: row - distance) {
                let position = ContentPosition(
                    block: above.block, line: above.line, offset: above.firstOffset + above.text.count)
                return LocatedPosition(position: position, ordinal: above.ordinal)
            }
            distance += 1
        }
        return nil
    }

    /// The cells to paint as selected, one span per visible row the selection touches.
    ///
    /// Only the intersection with what is on screen is returned, so a selection that is partly scrolled out of view highlights what
    /// is visible and keeps the rest anchored in the content. A row of an empty line has no cells and so no span.
    public func highlights<Content: SelectableContent>(
        of selection: ContentSelection<BlockID>, in content: Content, tabSize: Int = 4
    ) -> [HighlightSpan] where Content.BlockID == BlockID {
        guard !selection.isCollapsed, let (start, end) = selection.resolved(in: content) else { return [] }
        var spans: [HighlightSpan] = []
        for (row, entry) in rows.enumerated() {
            guard let source = entry else { continue }
            let here = (source.ordinal, source.line)
            guard here >= (start.ordinal, start.line), here <= (end.ordinal, end.line) else { continue }
            let rowEnd = source.firstOffset + source.text.count
            let from = here == (start.ordinal, start.line) ? max(source.firstOffset, start.offset) : source.firstOffset
            let to = here == (end.ordinal, end.line) ? min(rowEnd, end.offset) : rowEnd
            guard from < to else { continue }
            let startCol =
                source.col
                + TextDisplayMetrics.displayColumn(
                    forCharacterOffset: from - source.firstOffset, in: source.text, tabSize: tabSize)
            let endCol =
                source.col
                + TextDisplayMetrics.displayColumn(
                    forCharacterOffset: to - source.firstOffset, in: source.text, tabSize: tabSize)
            if endCol > startCol { spans.append(HighlightSpan(row: row, startCol: startCol, endCol: endCol)) }
        }
        return spans
    }
}

extension ContentSelection {
    private enum CharacterClass {
        case word
        case space
        case other

        init(_ character: Character) {
            if character.isLetter || character.isNumber || character == "_" {
                self = .word
            } else if character.isWhitespace {
                self = .space
            } else {
                self = .other
            }
        }
    }

    /// The run of like characters around a position, for a double click: letters, digits and `_` together, spaces together, and
    /// anything else together. Nil when the line is empty or the block is gone.
    public static func word<Content: SelectableContent>(at position: ContentPosition<BlockID>, in content: Content)
        -> Self?
    where Content.BlockID == BlockID {
        guard let ordinal = content.ordinal(of: position.block), position.line >= 0,
            position.line < content.lineCount(ofBlockAt: ordinal)
        else { return nil }
        let characters = Array(content.line(position.line, ofBlockAt: ordinal))
        guard !characters.isEmpty else { return nil }
        let at = min(max(position.offset, 0), characters.count - 1)
        let kind = CharacterClass(characters[at])
        var low = at
        var high = at + 1
        while low > 0, CharacterClass(characters[low - 1]) == kind { low -= 1 }
        while high < characters.count, CharacterClass(characters[high]) == kind { high += 1 }
        return Self(
            anchor: ContentPosition(block: position.block, line: position.line, offset: low),
            head: ContentPosition(block: position.block, line: position.line, offset: high))
    }

    /// The whole line around a position, for a triple click. Nil when the block is gone or the line does not exist.
    public static func line<Content: SelectableContent>(at position: ContentPosition<BlockID>, in content: Content)
        -> Self?
    where Content.BlockID == BlockID {
        guard let ordinal = content.ordinal(of: position.block), position.line >= 0,
            position.line < content.lineCount(ofBlockAt: ordinal)
        else { return nil }
        let length = content.line(position.line, ofBlockAt: ordinal).count
        return Self(
            anchor: ContentPosition(block: position.block, line: position.line, offset: 0),
            head: ContentPosition(block: position.block, line: position.line, offset: length))
    }
}
