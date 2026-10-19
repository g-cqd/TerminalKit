/// Bitset-based dirty region tracker for screen buffer.
public struct DirtyTracker: Sendable, Equatable {
    private var bits: ContiguousArray<UInt64>
    /// The words any mark has touched since the last clear, so clearing, testing and walking cost what was
    /// marked rather than the whole screen (roadmap 0008). Empty when `firstTouched > lastTouched`.
    private var firstTouched = Int.max
    private var lastTouched = -1
    public let capacity: Int

    public init(capacity: Int) {
        self.capacity = capacity
        let words = (capacity + 63) / 64
        self.bits = ContiguousArray<UInt64>(repeating: 0, count: words)
    }

    public mutating func mark(_ index: Int) {
        guard index >= 0, index < capacity else { return }
        let word = index >> 6  // / 64
        let bit = index & 63  // % 64
        bits[word] |= (1 &<< bit)
        touch(word, word)
    }

    /// Marks a contiguous range of indices dirty.
    public mutating func markRange(_ range: Range<Int>) {
        let lo = max(range.lowerBound, 0)
        let hi = min(range.upperBound, capacity)
        guard lo < hi else { return }

        let firstWord = lo >> 6
        let lastWord = (hi - 1) >> 6
        let firstBit = lo & 63
        let lastBit = (hi - 1) & 63
        touch(firstWord, lastWord)

        if firstWord == lastWord {
            let mask = (UInt64.max << firstBit) & (UInt64.max >> (63 - lastBit))
            bits[firstWord] |= mask
        } else {
            bits[firstWord] |= (UInt64.max << firstBit)
            for w in (firstWord + 1) ..< lastWord {
                bits[w] = UInt64.max
            }
            bits[lastWord] |= (UInt64.max >> (63 - lastBit))
        }
    }

    /// Marks all cells dirty in a single pass (O(words) instead of O(cells)).
    public mutating func markAll() {
        bits.withUnsafeMutableBufferPointer { buf in
            buf.update(repeating: UInt64.max)
        }
        touch(0, bits.count &- 1)
    }

    public func isDirty(_ index: Int) -> Bool {
        guard index >= 0, index < capacity else { return false }
        let word = index >> 6
        let bit = index & 63
        return (bits[word] & (1 &<< bit)) != 0
    }

    /// Calls `body` with every dirty index in ascending order, a word at a time: O(words + dirty), not
    /// O(capacity), so a frame that changed one cell does not visit the others.
    @inline(__always)
    func forEachDirtyIndex(_ body: (Int) -> Void) {
        guard firstTouched <= lastTouched else { return }
        let words = bits.span
        for word in firstTouched ... lastTouched {
            var remaining = words[word]
            // `markAll()` sets the last word's bits past `capacity` too; they name no cell.
            if word == words.count &- 1, capacity & 63 != 0 { remaining &= (1 &<< UInt64(capacity & 63)) &- 1 }
            while remaining != 0 {
                body(word &<< 6 &+ remaining.trailingZeroBitCount)
                remaining &= remaining &- 1
            }
        }
    }

    /// Whether any index in `range` is dirty, a word at a time.
    func isAnyDirty(in range: Range<Int>) -> Bool {
        let lo = max(range.lowerBound, 0)
        let hi = min(range.upperBound, capacity)
        guard lo < hi else { return false }
        let firstWord = lo >> 6
        let lastWord = (hi - 1) >> 6
        for word in firstWord ... lastWord {
            var mask = UInt64.max
            if word == firstWord { mask &= UInt64.max << (lo & 63) }
            if word == lastWord { mask &= UInt64.max >> (63 - ((hi - 1) & 63)) }
            if bits[word] & mask != 0 { return true }
        }
        return false
    }

    public mutating func clear() {
        guard firstTouched <= lastTouched else { return }
        let touched = firstTouched ... lastTouched
        var words = bits.mutableSpan
        for word in touched { words[word] = 0 }
        firstTouched = .max
        lastTouched = -1
    }

    public var isEmpty: Bool {
        // OR-reduce the touched words — any non-zero means dirty cells exist
        guard firstTouched <= lastTouched else { return true }
        let words = bits.span
        var acc: UInt64 = 0
        for word in firstTouched ... lastTouched { acc |= words[word] }
        return acc == 0
    }

    /// Two trackers are equal when they mark the same cells; which words were touched is bookkeeping.
    public static func == (lhs: DirtyTracker, rhs: DirtyTracker) -> Bool {
        lhs.capacity == rhs.capacity && lhs.bits == rhs.bits
    }

    @inline(__always)
    private mutating func touch(_ first: Int, _ last: Int) {
        if first < firstTouched { firstTouched = first }
        if last > lastTouched { lastTouched = last }
    }

    /// Returns ranges of contiguous dirty cells per row using word-level CTZ scanning.
    public func dirtyRanges(columns: Int) -> [(row: Int, colStart: Int, colEnd: Int)] {
        var ranges: [(row: Int, colStart: Int, colEnd: Int)] = []
        forEachDirtyRange(columns: columns) { row, colStart, colEnd in
            ranges.append((row: row, colStart: colStart, colEnd: colEnd))
        }
        return ranges
    }

    /// Calls `body` with each run of contiguous dirty cells, row by row, in order, without
    /// materializing them: the renderer walks these on every flush, which must not allocate.
    public func forEachDirtyRange(columns: Int, _ body: (_ row: Int, _ colStart: Int, _ colEnd: Int) -> Void) {
        guard columns > 0, firstTouched <= lastTouched else { return }
        let rows = capacity / columns
        // Only the rows the touched words cover can hold a dirty cell.
        let firstRow = (firstTouched &<< 6) / columns
        let endRow = Swift.min(rows, ((lastTouched &+ 1) &<< 6 &+ columns &- 1) / columns)

        for row in firstRow ..< Swift.max(firstRow, endRow) {
            let rowStart = row * columns
            var col = 0
            while col < columns {
                let idx = rowStart + col
                let word = idx >> 6
                let bit = idx & 63

                // Fast skip: if the remaining bits in this word are all zero, advance
                let masked = bits[word] >> bit
                if masked == 0 {
                    // Skip to next word boundary
                    let remaining = 64 - bit
                    col += remaining
                    continue
                }

                // Find first set bit from current position
                let offset = masked.trailingZeroBitCount
                if col + offset >= columns {
                    break
                }
                let dirtyStart = col + offset
                col = dirtyStart

                // Find end of dirty run
                while col < columns {
                    let idx2 = rowStart + col
                    let w2 = idx2 >> 6
                    let b2 = idx2 & 63
                    if (bits[w2] & (1 &<< b2)) == 0 { break }
                    col += 1
                }

                body(row, dirtyStart, col)
            }
        }
    }
}
