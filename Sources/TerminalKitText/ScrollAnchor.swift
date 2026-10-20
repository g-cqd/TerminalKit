/// A place in a stack of blocks that stays put when blocks above it change height: a block, and a row within it.
public struct ScrollAnchor<ID: Hashable & Sendable>: Sendable, Equatable {
    public var block: ID
    public var rowInBlock: Int

    public init(block: ID, rowInBlock: Int) {
        self.block = block
        self.rowInBlock = rowInBlock
    }
}

/// The heights of a stack of blocks in rows, in reading order, so a scroll position can be kept through a fold.
///
/// Folding or unfolding a block changes the height of everything below it, and a reader must not feel the text move: whatever was at
/// the top of the screen stays there. The host takes the anchor *before* the change, and asks where to scroll *after*.
public struct BlockHeights<ID: Hashable & Sendable>: Sendable {
    private var order: [ID] = []
    private var heights: [Int] = []
    private var firstRows: [ID: Int] = [:]
    private var total = 0

    public init() {}

    /// The number of rows in all the blocks.
    public var rowCount: Int { total }

    /// Adds the next block, below the ones already there. A height below one counts as one.
    public mutating func append(_ id: ID, height: Int) {
        let rows = max(1, height)
        firstRows[id] = total
        order.append(id)
        heights.append(rows)
        total += rows
    }

    /// The row a block starts at, or nil if it is not here.
    public func firstRow(of id: ID) -> Int? { firstRows[id] }

    /// The anchor for the block and row at a row of the stack, or nil past the end.
    public func anchor(atRow row: Int) -> ScrollAnchor<ID>? {
        guard row >= 0, row < total else { return nil }
        var low = 0
        var high = order.count - 1
        while low < high {
            let middle = (low + high + 1) / 2
            if firstRows[order[middle]] ?? 0 <= row { low = middle } else { high = middle - 1 }
        }
        return ScrollAnchor(block: order[low], rowInBlock: row - (firstRows[order[low]] ?? 0))
    }

    /// The row an anchor is at now. A row beyond the end of its block, such as one inside a block that has just folded, is clamped to
    /// the block's last row. Nil if the block is gone.
    public func row(of anchor: ScrollAnchor<ID>) -> Int? {
        guard let first = firstRows[anchor.block], let index = order.firstIndex(of: anchor.block) else { return nil }
        return first + min(max(anchor.rowInBlock, 0), heights[index] - 1)
    }

    /// Where to scroll so that `anchor` stays at screen row `screenRow`: the new offset of the first visible row, never below zero and
    /// never past the point where the last row would leave blank space below it.
    public func scrollOffset(keeping anchor: ScrollAnchor<ID>, atScreenRow screenRow: Int, viewportRows: Int) -> Int? {
        guard let row = row(of: anchor) else { return nil }
        let wanted = row - screenRow
        return min(max(wanted, 0), max(0, total - viewportRows))
    }
}
