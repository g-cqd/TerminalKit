import Testing

@testable import TerminalKitCodecs
@testable import TerminalKitIO
@testable import TerminalKitRender

@Suite
struct DirtyTrackerTests {
    @Test
    func `Mark and check dirty`() {
        var tracker = DirtyTracker(capacity: 100)
        #expect(!tracker.isDirty(5))
        tracker.mark(5)
        #expect(tracker.isDirty(5))
        #expect(!tracker.isDirty(4))
    }

    @Test
    func `Out of bounds indices are ignored`() {
        var tracker = DirtyTracker(capacity: 10)

        tracker.mark(-1)
        tracker.mark(10)

        #expect(!tracker.isDirty(-1))
        #expect(!tracker.isDirty(10))
        #expect(tracker.isEmpty)
    }

    @Test
    func `Clear resets all bits`() {
        var tracker = DirtyTracker(capacity: 100)
        tracker.mark(0)
        tracker.mark(99)
        tracker.clear()
        #expect(tracker.isEmpty)
    }

    @Test
    func `Dirty ranges`() {
        var tracker = DirtyTracker(capacity: 30)  // 10 cols × 3 rows
        tracker.mark(10)  // row 1, col 0
        tracker.mark(11)  // row 1, col 1
        tracker.mark(12)  // row 1, col 2
        let ranges = tracker.dirtyRanges(columns: 10)
        #expect(ranges.count == 1)
        #expect(ranges[0].row == 1)
        #expect(ranges[0].colStart == 0)
        #expect(ranges[0].colEnd == 3)
    }
}

@Suite("Dirty indices are walked a word at a time")
struct DirtyIndexWalkTests {
    @Test func `every dirty index is visited once, in order, and no other`() {
        var tracker = DirtyTracker(capacity: 300)
        let marked = [0, 1, 63, 64, 65, 127, 128, 200, 299]
        for index in marked { tracker.mark(index) }

        var visited: [Int] = []
        tracker.forEachDirtyIndex { visited.append($0) }

        #expect(visited == marked)
    }

    @Test func `marking everything visits every index and none past the capacity`() {
        // markAll sets whole words, so the last word holds bits beyond a capacity that is not a multiple of 64.
        var tracker = DirtyTracker(capacity: 100)
        tracker.markAll()

        var visited: [Int] = []
        tracker.forEachDirtyIndex { visited.append($0) }

        #expect(visited == Array(0 ..< 100))
    }

    @Test func `clearing then marking elsewhere reports only the new marks`() {
        // The tracker remembers which words were touched; a clear must forget them, and a later mark far away
        // must still be found by every query.
        var tracker = DirtyTracker(capacity: 1_000)
        tracker.markRange(10 ..< 20)
        tracker.clear()
        tracker.mark(900)

        var visited: [Int] = []
        tracker.forEachDirtyIndex { visited.append($0) }
        #expect(visited == [900])
        #expect(!tracker.isEmpty)
        #expect(tracker.dirtyRanges(columns: 100).map { [$0.row, $0.colStart, $0.colEnd] } == [[9, 0, 1]])
        tracker.clear()
        #expect(tracker.isEmpty)
        #expect(tracker == DirtyTracker(capacity: 1_000))
    }

    @Test func `an empty tracker visits nothing`() {
        var visited = 0
        DirtyTracker(capacity: 1_000).forEachDirtyIndex { _ in visited += 1 }

        #expect(visited == 0)
    }
}
