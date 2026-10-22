/// A bounded window over an ``InputLayout`` that keeps a source cursor visible. The host chooses the row cap.
/// Retain `visibleRows.lowerBound` as the next `firstRow` to avoid moving a window that already contains the cursor.
public struct InputViewport: Sendable, Equatable {
    /// The display rows to draw.
    public let visibleRows: Range<Int>
    /// The cursor relative to the visible window.
    public let cursor: InputLayout.Position
    public let rowsAbove: Int
    public let rowsBelow: Int

    /// Clamps the requested window and moves it only as far as needed to show the cursor.
    /// - Complexity: O(1), including mapping the source cursor through the layout.
    public init(layout: InputLayout, cursorOffset: Int, maximumRows: Int, firstRow: Int = 0) {
        let position = layout.position(at: cursorOffset)
        let height = min(layout.rows.count, max(1, maximumRows))
        var first = min(max(0, firstRow), layout.rows.count - height)
        if position.row < first {
            first = position.row
        } else if position.row >= first + height {
            first = position.row - height + 1
        }
        visibleRows = first ..< first + height
        cursor = .init(row: position.row - first, column: position.column)
        rowsAbove = first
        rowsBelow = layout.rows.count - visibleRows.upperBound
    }
}
