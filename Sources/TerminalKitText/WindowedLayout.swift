/// A document laid out item by item, of which only the lines near what is shown are kept (roadmap 0023).
///
/// ``LayoutCache`` keeps every line of every item. This keeps every item's **row count** and the lines of the items near the rows asked
/// for, so a long document costs a few integers per item, not its whole laid-out text. Resident memory falls only when pages are never
/// touched: an item's lines are laid out to count its rows and let go at once unless they are near the end, where the screen usually is.
///
/// Items carry revisions, as for ``LayoutCache``: an item whose revision is unchanged is not laid out again for its height, so a revision
/// must change whenever what the item lays out to would. A streamed reply changes only the last item: a frame lays out that one.
public struct WindowedLayout<Line: Sendable>: Sendable {
    /// The rows of the whole document at the last width.
    public private(set) var rowCount = 0

    /// Each item's revision when it was last laid out, its rows, and the row it starts at.
    private var revisions: [Int] = []
    private var heights: [Int] = []
    private var starts: [Int] = []
    /// The lines of the items kept, by item.
    private var held: [Int: [Line]] = [:]
    private var width = -1

    /// How many rows beyond the asked-for window an item may be and keep its lines; nil keeps one window's worth on each side.
    public var margin: Int?

    public init(margin: Int? = nil) { self.margin = margin }

    /// The items whose lines are kept, in order: for tests and measurements.
    public var heldItems: [Int] { held.keys.sorted() }

    /// Brings the row counts up to date with a document of `revisions.count` items.
    ///
    /// - Parameters:
    ///   - width: the width the lines are laid out at. A change lays everything out again.
    ///   - current: each item's current revision.
    ///   - rows: an item ending within this many rows of the document's end keeps the lines laid out for its height.
    ///   - layout: the lines of item `index`, called for the items that changed, last first.
    /// - Complexity: O(items) to compare revisions and place the items, plus the layout of the changed items.
    public mutating func update(width: Int, revisions current: [Int], keepingFromEnd rows: Int, layout: (Int) -> [Line])
    {
        if width != self.width {
            reset()
            self.width = width
        }
        let kept = Swift.min(revisions.count, current.count)
        let firstChanged = (0 ..< kept).first { revisions[$0] != current[$0] } ?? kept
        if firstChanged < revisions.count {
            revisions.removeSubrange(firstChanged...)
            heights.removeSubrange(firstChanged...)
            starts.removeSubrange(firstChanged...)
            held = held.filter { $0.key < firstChanged }
        }
        guard firstChanged < current.count else {
            rowCount = (starts.last ?? 0) + (heights.last ?? 0)
            return
        }
        // Last first, so how far an item ends from the document's end is known when its lines are laid out: every item after a changed
        // one changed too.
        var changedHeights = [Int](repeating: 0, count: current.count - firstChanged)
        var fromEnd = 0
        for index in (firstChanged ..< current.count).reversed() {
            let lines = layout(index)
            changedHeights[index - firstChanged] = lines.count
            if fromEnd < rows { held[index] = lines }
            fromEnd += lines.count
        }
        var start = (starts.last ?? 0) + (heights.last ?? 0)
        for (offset, height) in changedHeights.enumerated() {
            revisions.append(current[firstChanged + offset])
            heights.append(height)
            starts.append(start)
            start += height
        }
        rowCount = start
    }

    /// The lines of document rows `range`, clamped to the document: items not kept are laid out, and kept items farther than the margin
    /// from `range` are let go.
    ///
    /// - Parameters:
    ///   - range: the document rows wanted.
    ///   - layout: the lines of item `index`, the same function ``update(width:revisions:keepingFromEnd:layout:)`` was given.
    /// - Returns: the lines of those rows, in order.
    /// - Complexity: O(log items) to find the first item, plus the items in the window and those kept.
    public mutating func lines(in range: Range<Int>, layout: (Int) -> [Line]) -> [Line] {
        let wanted = range.clamped(to: 0 ..< rowCount)
        let reach = margin ?? wanted.count
        let keep = (wanted.lowerBound - reach) ..< (wanted.upperBound + reach)
        for index in held.keys where !overlaps(index, keep) { held[index] = nil }
        guard !wanted.isEmpty else { return [] }
        var result: [Line] = []
        result.reserveCapacity(wanted.count)
        var index = item(atRow: wanted.lowerBound)
        while index < starts.count, starts[index] < wanted.upperBound {
            // An empty item shows nothing: it is never laid out again for the window.
            if heights[index] == 0 {
                index += 1
                continue
            }
            let lines = held[index] ?? layout(index)
            held[index] = lines
            let from = Swift.max(0, wanted.lowerBound - starts[index])
            let to = Swift.min(lines.count, wanted.upperBound - starts[index])
            if from < to { result += lines[from ..< to] }
            index += 1
        }
        return result
    }

    /// The item that row `row` belongs to: the last item starting at or before it.
    public func item(atRow row: Int) -> Int {
        var low = 0
        var high = starts.count
        while low < high {
            let middle = (low + high) / 2
            if starts[middle] <= row { low = middle + 1 } else { high = middle }
        }
        return Swift.max(0, low - 1)
    }

    /// The rows item `index` occupies.
    public func rows(of index: Int) -> Range<Int> { starts[index] ..< starts[index] + heights[index] }

    private func overlaps(_ index: Int, _ rows: Range<Int>) -> Bool {
        index < starts.count && self.rows(of: index).overlaps(rows)
    }

    /// Forgets every item, so the next update lays out everything.
    public mutating func reset() {
        revisions.removeAll(keepingCapacity: true)
        heights.removeAll(keepingCapacity: true)
        starts.removeAll(keepingCapacity: true)
        held.removeAll()
        rowCount = 0
        width = -1
    }
}
