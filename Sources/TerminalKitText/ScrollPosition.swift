/// How far a stack of rows is scrolled up from its end, and the rules for moving it (ask roadmap 0125, kit roadmap 0021).
///
/// A transcript follows its end: at zero it shows the last row, and a row that arrives is seen. Scrolling up moves the view away from the end,
/// and while it is away new rows do not move it. These rules were written three times in `ask` (the wheel, the Page keys and a fold that
/// changes the height above the reader); a host takes them from here so that they cannot differ.
public struct ScrollPosition: Sendable, Equatable {
    /// How many rows the view is scrolled up from the end. Zero follows the end.
    public var rowsFromEnd: Int

    public init(rowsFromEnd: Int = 0) { self.rowsFromEnd = max(0, rowsFromEnd) }

    /// Whether the view is at the end, following new rows.
    public var followsEnd: Bool { rowsFromEnd == 0 }

    /// How far up the view can go: until the first row is the one at the top of the viewport.
    public static func furthest(totalRows: Int, viewportRows: Int) -> Int { max(0, totalRows - viewportRows) }

    /// Moves the view up by `rows`, or down for a negative number, and no further than the first row at the top or the end at the bottom.
    ///
    /// A position already past the top, because rows were removed since, is left where it is rather than pulled back by a scroll up.
    public mutating func scroll(by rows: Int, totalRows: Int, viewportRows: Int) {
        let furthest = Self.furthest(totalRows: totalRows, viewportRows: viewportRows)
        rowsFromEnd = max(0, min(rowsFromEnd + rows, max(furthest, rowsFromEnd)))
    }

    /// Whether a scroll up would move the view.
    public func canScrollUp(totalRows: Int, viewportRows: Int) -> Bool {
        Self.furthest(totalRows: totalRows, viewportRows: viewportRows) > rowsFromEnd
    }

    /// Whether a scroll down would move the view.
    public var canScrollDown: Bool { rowsFromEnd > 0 }

    /// Goes back to following the end.
    public mutating func followEnd() { rowsFromEnd = 0 }

    /// Keeps the reader's place when the height of what is above it changes by `delta` rows, such as a fold opening: the view moves by as
    /// much and what was on screen stays on its row. At the end it does nothing, as the view follows the end anyway.
    public mutating func keepPlace(whenRowsAboveChangeBy delta: Int) {
        if rowsFromEnd > 0 { rowsFromEnd = max(0, rowsFromEnd + delta) }
    }

    /// The index of the first row on screen, in a stack of `totalRows` rows shown through a viewport of `viewportRows`.
    public func firstVisibleRow(totalRows: Int, viewportRows: Int) -> Int {
        max(0, totalRows - rowsFromEnd - viewportRows)
    }
}
