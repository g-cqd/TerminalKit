/// A document laid out item by item from its end, of which only the rows near what is shown are ever built (roadmap 0023).
///
/// ``LayoutCache`` keeps every line of every item. This knows the **row counts of the last items only**, as many as the rows asked for
/// need, and keeps the lines of the items near them. A document opened or laid out at a new width costs the rows on screen and a margin,
/// not its whole length; scrolling up lays out the items it reaches. Resident memory falls only when pages are never touched, so the
/// lines of an item far from the window are never built at all.
///
/// Positions count from the document's **end**, as a transcript that follows its end does: the rows below any window are exact, and
/// ``rowCount`` is the rows of the items known so far, which grows as a window moves up and is the whole document once ``isComplete``.
///
/// Items carry revisions, as for ``LayoutCache``: an item whose revision is unchanged is not laid out again for its height, so a revision
/// must change whenever what the item lays out to would. A streamed reply changes only the last item: a frame lays out that one.
public struct WindowedLayout<Line: Sendable>: Sendable {
    /// The rows of the items whose heights are known: the last ones, from ``firstKnown`` to the end.
    public var rowCount: Int { firstKnown < heights.count ? end - starts[firstKnown] : 0 }
    /// The first item whose height is known; every item after it is known too.
    public private(set) var firstKnown = 0

    /// For a known item, the revision it was laid out from; for one before ``firstKnown``, its latest revision.
    private var revisions: [Int] = []
    private var heights: [Int] = []
    /// Where each known item starts, in rows of a coordinate that neither appending nor reaching back moves: the first item reached
    /// ends at zero, the ones before it start below zero.
    private var starts: [Int] = []
    /// The lines of the items kept, by item.
    private var held: [Int: [Line]] = [:]
    private var width = -1

    /// How many rows beyond the asked-for window an item may be and keep its lines; nil keeps one window's worth on each side.
    public var margin: Int?

    public init(margin: Int? = nil) { self.margin = margin }

    /// Whether every item's height is known, so that ``rowCount`` is the whole document's.
    public var isComplete: Bool { firstKnown == 0 }

    /// The items whose lines are kept, in order: for tests and measurements.
    public var heldItems: [Int] { held.keys.sorted() }

    /// Brings the document up to `revisions.count` items, and the last `rows` rows' heights up to date.
    ///
    /// - Parameters:
    ///   - width: the width the lines are laid out at. A change forgets every height.
    ///   - current: each item's current revision.
    ///   - rows: the rows from the end whose items must be known; their lines are kept.
    ///   - layout: the lines of item `index`, called for the items that changed and those newly reached, last first.
    /// - Complexity: O(items) to compare revisions and move positions, plus the layout of the changed items and of those newly reached.
    public mutating func update(width: Int, revisions current: [Int], keepingFromEnd rows: Int, layout: (Int) -> [Line])
    {
        if width != self.width {
            reset()
            self.width = width
        }
        // A shorter document forgets the items it no longer has; a changed item that is known is laid out again alone, and the items
        // after it move by the rows it gained or lost (ask's roadmap 0158: forgetting everything after it cost seconds at the top).
        forget(from: current.count)
        let kept = revisions.count
        for index in 0 ..< Swift.min(firstKnown, kept) { revisions[index] = current[index] }
        relayOutChanged(current, layout: layout)
        if firstKnown == revisions.count {
            // Nothing is known: the new items wait to be reached from the end, like the rest.
            revisions += current[revisions.count...]
            heights += repeatElement(0, count: current.count - heights.count)
            starts += repeatElement(0, count: current.count - starts.count)
            firstKnown = revisions.count
        } else {
            // The known rows run to the end, so the new items after them are laid out now, last first.
            var fromEnd = 0
            var added: [Int] = []
            for index in (revisions.count ..< current.count).reversed() {
                let lines = layout(index)
                if fromEnd < rows { held[index] = lines }
                fromEnd += lines.count
                added.append(lines.count)
            }
            var start = end
            for height in added.reversed() {
                starts.append(start)
                heights.append(height)
                start += height
            }
            revisions += current[revisions.count...]
        }
        reach(rows, keeping: rows, layout: layout)
    }

    /// The lines of the `rows` rows that end `fromEnd` rows above the document's end, fewer at the top: the items not kept are laid out,
    /// and kept items farther than the margin are let go.
    ///
    /// - Parameters:
    ///   - fromEnd: how many rows below the window, to the end.
    ///   - rows: the window's height.
    ///   - layout: the lines of item `index`, the same function ``update(width:revisions:keepingFromEnd:layout:)`` was given.
    /// - Returns: the lines of those rows, in order.
    /// - Complexity: O(log items) to find the window, plus the items kept and the layout of those newly reached or shown.
    public mutating func lines(fromEnd: Int, rows: Int, layout: (Int) -> [Line]) -> [Line] {
        let reachRows = margin ?? rows
        reach(fromEnd + rows + reachRows, keeping: 0, layout: layout)
        guard firstKnown < heights.count else { return [] }
        // In this layout's coordinate: the window, and what may keep its lines.
        let top = starts[firstKnown]
        let wanted = Swift.max(top, end - fromEnd - rows) ..< Swift.max(top, end - fromEnd)
        let keep = (wanted.lowerBound - reachRows) ..< (wanted.upperBound + reachRows)
        for index in held.keys where !(starts[index] ..< starts[index] + heights[index]).overlaps(keep) {
            held[index] = nil
        }
        var result: [Line] = []
        result.reserveCapacity(wanted.count)
        var index = firstEnding(after: wanted.lowerBound)
        while index < heights.count, starts[index] < wanted.upperBound {
            // An empty item shows nothing, and is not laid out for it.
            if heights[index] > 0 {
                let lines = held[index] ?? layout(index)
                held[index] = lines
                let from = Swift.max(0, wanted.lowerBound - starts[index])
                let to = Swift.min(heights[index], wanted.upperBound - starts[index])
                result += lines[from ..< to]
            }
            index += 1
        }
        return result
    }

    /// Lays out each known item whose revision changed, in one pass that moves every later item by the rows the earlier ones gained or
    /// lost. A changed item keeps its new lines when it was keeping lines; a window that shows it lays out any other.
    private mutating func relayOutChanged(_ current: [Int], layout: (Int) -> [Line]) {
        guard firstKnown < revisions.count else { return }
        var shift = 0
        for index in firstKnown ..< revisions.count {
            starts[index] += shift
            guard revisions[index] != current[index] else { continue }
            revisions[index] = current[index]
            let lines = layout(index)
            shift += lines.count - heights[index]
            heights[index] = lines.count
            if held[index] != nil { held[index] = lines }
        }
    }

    /// Where the known rows end, in this layout's coordinate.
    private var end: Int { firstKnown < heights.count ? starts[heights.count - 1] + heights[heights.count - 1] : 0 }

    /// The first known item that ends after `row`.
    private func firstEnding(after row: Int) -> Int {
        var low = firstKnown
        var high = heights.count
        while low < high {
            let middle = (low + high) / 2
            if starts[middle] + heights[middle] <= row { low = middle + 1 } else { high = middle }
        }
        return low
    }

    /// Lays out items before ``firstKnown`` until `rows` rows from the end are known, keeping the lines of those within `keeping`.
    private mutating func reach(_ rows: Int, keeping: Int, layout: (Int) -> [Line]) {
        while rowCount < rows, firstKnown > 0 {
            let below = rowCount
            let next = firstKnown < heights.count ? starts[firstKnown] : 0
            firstKnown -= 1
            let lines = layout(firstKnown)
            if below < keeping { held[firstKnown] = lines }
            heights[firstKnown] = lines.count
            starts[firstKnown] = next - lines.count
        }
    }

    /// Forgets item `index` and every item after it, which the next update brings back from the current revisions.
    private mutating func forget(from index: Int) {
        guard index < revisions.count else { return }
        revisions.removeSubrange(index...)
        heights.removeSubrange(index...)
        starts.removeSubrange(index...)
        held = held.filter { $0.key < index }
        firstKnown = Swift.min(firstKnown, index)
    }

    /// Forgets every item, so the next update lays out from the end again.
    public mutating func reset() {
        revisions.removeAll(keepingCapacity: true)
        heights.removeAll(keepingCapacity: true)
        starts.removeAll(keepingCapacity: true)
        held.removeAll()
        firstKnown = 0
        width = -1
    }
}
