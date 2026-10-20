/// A direction the content should scroll in, asked of the host when a drag reaches an edge.
public enum ScrollRequest: Sendable, Equatable {
    case up
    case down
}

/// Turns a press, a drag, a release and a click into a selection (roadmap 0017).
///
/// It keeps the selection as **content positions**, so the host can scroll while a drag is in progress, and hands it each frame's
/// ``RowMap`` to find where the pointer is. A drag includes the grapheme under the pointer at its end and the one under the press at
/// its start, in either direction: the press is remembered as both its leading and its trailing edge, and the one that belongs is
/// chosen by which way the drag has gone. Whether the text is copied when it ends is the host's setting (ADR-0027).
public struct SelectionController<BlockID: Hashable & Sendable>: Sendable {
    /// What a call changed, and what the host should do about it.
    public struct Update: Sendable, Equatable {
        /// The selection changed, so the highlight must be repainted.
        public var changed = false
        /// A selection was completed, by a drag ending or a double or triple click: the host may copy it.
        public var committed = false
        /// The pointer is at the edge of the visible content and the host should scroll.
        public var scroll: ScrollRequest?

        public init(changed: Bool = false, committed: Bool = false, scroll: ScrollRequest? = nil) {
            self.changed = changed
            self.committed = committed
            self.scroll = scroll
        }
    }

    public private(set) var selection: ContentSelection<BlockID>?
    private var anchorBefore: LocatedPosition<BlockID>?
    private var anchorAfter: LocatedPosition<BlockID>?
    private var dragging = false
    private var press: (row: Int, col: Int)?

    public init() {}

    /// Whether a drag is in progress.
    public var isDragging: Bool { dragging }

    private static func ordered(_ lhs: LocatedPosition<BlockID>, _ rhs: LocatedPosition<BlockID>) -> Bool {
        (lhs.ordinal, lhs.position.line, lhs.position.offset) <= (rhs.ordinal, rhs.position.line, rhs.position.offset)
    }

    /// Starts a drag at a cell. A cell over padding snaps to the nearest row that has content.
    public mutating func beginDrag(row: Int, col: Int, rows: RowMap<BlockID>) -> Update {
        let had = selection != nil
        guard let before = rows.nearestPosition(row: row, col: col, edge: .leading),
            let after = rows.nearestPosition(row: row, col: col, edge: .trailing)
        else {
            selection = nil
            dragging = false
            return Update(changed: had)
        }
        anchorBefore = before
        anchorAfter = after
        dragging = true
        press = (row, col)
        selection = nil
        return Update(changed: had)
    }

    /// Extends the drag to a cell.
    ///
    /// - Parameters:
    ///   - row: The pointer's row.
    ///   - col: The pointer's column.
    ///   - rows: This frame's rows, so the pointer is found in the content as it is drawn now.
    ///   - scrollableRows: The rows that show scrolling content. A pointer on the first or last of them asks for a scroll, which the
    ///     host answers by moving the content and calling this again with the next frame's rows.
    /// - Returns: What changed, and whether the host should scroll.
    public mutating func drag(row: Int, col: Int, rows: RowMap<BlockID>, scrollableRows: Range<Int>) -> Update {
        // Motion inside the cell that was pressed is a click that wobbled, not a drag: with copy on select it would replace the
        // clipboard with one grapheme.
        if let press, press.row == row, press.col == col { return Update() }
        press = nil
        guard dragging, let before = anchorBefore, let after = anchorAfter,
            let headLeading = rows.nearestPosition(row: row, col: col, edge: .leading)
        else { return Update() }
        let forward = Self.ordered(before, headLeading)
        let anchor = forward ? before : after
        let head =
            forward ? (rows.nearestPosition(row: row, col: col, edge: .trailing) ?? headLeading) : headLeading
        let next = ContentSelection(anchor: anchor.position, head: head.position)
        var update = Update(changed: next != selection)
        selection = next.isCollapsed ? nil : next
        if row <= scrollableRows.lowerBound {
            update.scroll = .up
        } else if row >= scrollableRows.upperBound - 1 {
            update.scroll = .down
        }
        return update
    }

    /// Ends the drag. A selection that covers something is complete and may be copied; a drag that never moved selects nothing.
    public mutating func endDrag() -> Update {
        guard dragging else { return Update() }
        dragging = false
        guard let selection, !selection.isCollapsed else {
            let had = selection != nil
            self.selection = nil
            return Update(changed: had)
        }
        return Update(committed: true)
    }

    /// A click. One clears the selection; two select the word under the pointer and three the line, completing a selection that
    /// may be copied.
    public mutating func click<Content: SelectableContent>(
        row: Int, col: Int, count: Int, rows: RowMap<BlockID>, content: Content
    ) -> Update where Content.BlockID == BlockID {
        dragging = false
        let had = selection != nil
        guard count >= 2, let located = rows.position(row: row, col: col, edge: .leading) else {
            selection = nil
            return Update(changed: had)
        }
        let made =
            count == 2
            ? ContentSelection<BlockID>.word(at: located.position, in: content)
            : ContentSelection<BlockID>.line(at: located.position, in: content)
        selection = made
        return Update(changed: made != nil || had, committed: made != nil)
    }

    /// Forgets the selection and any drag, such as when the conversation is cleared.
    public mutating func clear() {
        selection = nil
        anchorBefore = nil
        anchorAfter = nil
        dragging = false
        press = nil
    }
}

/// Splits a row's text at the cells of a highlight, so the middle can be painted selected.
public enum ColumnSlicer {
    /// The text before, inside and after a run of columns, counted from the start of `text`. Wide graphemes and tabs are measured as
    /// ``TextDisplayMetrics`` measures them, and the split is always at a grapheme boundary.
    public static func split(_ text: String, columns: Range<Int>, tabSize: Int = 4) -> (
        before: String, selected: String, after: String
    ) {
        let low = TextDisplayMetrics.characterOffset(
            forDisplayColumn: max(0, columns.lowerBound), in: text, tabSize: tabSize)
        let high = max(
            low,
            TextDisplayMetrics.characterOffset(forDisplayColumn: max(0, columns.upperBound), in: text, tabSize: tabSize)
        )
        let characters = text.count
        let start = text.index(text.startIndex, offsetBy: min(low, characters))
        let end = text.index(start, offsetBy: min(high, characters) - min(low, characters))
        return (String(text[..<start]), String(text[start ..< end]), String(text[end...]))
    }
}
