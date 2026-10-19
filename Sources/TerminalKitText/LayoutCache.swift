/// The lines of a document laid out item by item, kept between frames, and rebuilt only from the first item
/// that changed (roadmap 0012).
///
/// A document is a list of items, such as a transcript's messages. Each has a revision that changes when its
/// content does, and lays out into any number of lines at a width. A streamed reply changes only the last
/// item, so a frame lays out that one and keeps every line before it, rather than all of them again.
///
/// The cache trusts revisions: an item whose revision is unchanged is not laid out again, so a revision must
/// change whenever what the item lays out to would.
public struct LayoutCache<Line: Sendable>: Sendable {
    /// Every item's lines, end to end.
    public private(set) var lines: [Line] = []

    /// Where each item's lines start in ``lines``, and the revision they were laid out from.
    private var starts: [Int] = []
    private var laidOutRevisions: [Int] = []
    private var width = -1

    public init() {}

    /// Brings ``lines`` up to date with a document of `revisions.count` items.
    ///
    /// - Parameters:
    ///   - width: the width the lines are laid out at. A change lays everything out again.
    ///   - revisions: each item's current revision.
    ///   - layout: the lines of item `index`, called for the items that need them, in order.
    /// - Complexity: O(items) to compare revisions, plus the layout of the changed items.
    public mutating func update(width: Int, revisions: [Int], layout: (Int) -> [Line]) {
        if width != self.width {
            reset()
            self.width = width
        }
        let kept = Swift.min(laidOutRevisions.count, revisions.count)
        var firstChanged = kept
        for index in 0 ..< kept where laidOutRevisions[index] != revisions[index] {
            firstChanged = index
            break
        }
        if firstChanged < laidOutRevisions.count {
            lines.removeSubrange(starts[firstChanged]...)
            starts.removeSubrange(firstChanged...)
            laidOutRevisions.removeSubrange(firstChanged...)
        }
        for index in firstChanged ..< revisions.count {
            starts.append(lines.count)
            lines += layout(index)
            laidOutRevisions.append(revisions[index])
        }
    }

    /// Forgets every line, so the next update lays out everything.
    public mutating func reset() {
        lines.removeAll(keepingCapacity: true)
        starts.removeAll(keepingCapacity: true)
        laidOutRevisions.removeAll(keepingCapacity: true)
        width = -1
    }
}
