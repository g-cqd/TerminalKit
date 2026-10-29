import Testing

@testable import TerminalKitText

/// A long document of which only the rows near the window are kept (roadmap 0023): every item's height is known, its lines are not.
@Suite("A windowed layout keeps heights for every item and lines only near the window")
struct WindowedLayoutTests {
    private final class Calls {
        var items: [Int] = []
    }

    /// Item `n` lays out to `n % 3 + 1` lines, so items differ in height.
    private static func lines(of item: Int, revision: Int) -> [String] {
        (0 ..< item % 3 + 1).map { "item \(item) rev \(revision) line \($0)" }
    }

    private func update(
        _ layout: inout WindowedLayout<String>, width: Int = 10, revisions: [Int], keeping rows: Int = 0, calls: Calls
    ) {
        layout.update(width: width, revisions: revisions, keepingFromEnd: rows) { item in
            calls.items.append(item)
            return Self.lines(of: item, revision: revisions[item])
        }
    }

    private func window(
        _ layout: inout WindowedLayout<String>, _ rows: Range<Int>, revisions: [Int], calls: Calls
    ) -> [String] {
        layout.lines(in: rows) { item in
            calls.items.append(item)
            return Self.lines(of: item, revision: revisions[item])
        }
    }

    /// Every line of the document end to end, as ``LayoutCache`` would hold it.
    private func flat(_ revisions: [Int]) -> [String] {
        revisions.indices.flatMap { Self.lines(of: $0, revision: revisions[$0]) }
    }

    @Test func `the first update counts every item's rows and keeps only the end`() {
        var layout = WindowedLayout<String>()
        let calls = Calls()
        let revisions = [Int](repeating: 0, count: 100)
        update(&layout, revisions: revisions, keeping: 5, calls: calls)
        #expect(layout.rowCount == flat(revisions).count)
        #expect(calls.items == Array((0 ..< 100).reversed()), "laid out last first, once each")
        #expect(layout.heldItems == [97, 98, 99], "the items ending within 5 rows of the end")
    }

    @Test func `a window anywhere shows the same lines as the whole document`() {
        var layout = WindowedLayout<String>()
        let calls = Calls()
        let revisions = [Int](repeating: 0, count: 50)
        update(&layout, revisions: revisions, calls: calls)
        let all = flat(revisions)
        for range in [0 ..< 7, 13 ..< 31, 90 ..< all.count, 95 ..< 200] {
            let expected = Array(all[range.clamped(to: 0 ..< all.count)])
            #expect(window(&layout, range, revisions: revisions, calls: calls) == expected)
        }
    }

    @Test func `the window lays out only the items it shows, and lets far ones go`() {
        var layout = WindowedLayout<String>(margin: 0)
        let calls = Calls()
        let revisions = [Int](repeating: 0, count: 50)
        update(&layout, revisions: revisions, keeping: 3, calls: calls)
        calls.items = []
        // Rows 0 to 5 are items 0 (1 row), 1 (2 rows) and 2 (3 rows).
        _ = window(&layout, 0 ..< 6, revisions: revisions, calls: calls)
        #expect(calls.items == [0, 1, 2])
        #expect(layout.heldItems == [0, 1, 2], "the end's items are let go once out of reach")
        calls.items = []
        _ = window(&layout, 1 ..< 6, revisions: revisions, calls: calls)
        #expect(calls.items.isEmpty, "kept between frames")
        #expect(layout.heldItems == [1, 2])
    }

    @Test func `streaming the last item lays out only that item`() {
        var layout = WindowedLayout<String>()
        let calls = Calls()
        var revisions = [Int](repeating: 0, count: 40)
        update(&layout, revisions: revisions, keeping: 10, calls: calls)
        let end = layout.rowCount
        _ = window(&layout, end - 10 ..< end, revisions: revisions, calls: calls)
        calls.items = []
        revisions[39] = 1
        update(&layout, revisions: revisions, keeping: 10, calls: calls)
        let shown = window(&layout, layout.rowCount - 10 ..< layout.rowCount, revisions: revisions, calls: calls)
        #expect(calls.items == [39])
        #expect(shown.last == "item 39 rev 1 line 0")
    }

    @Test func `a changed item in the middle moves the rows after it`() {
        var layout = WindowedLayout<String>()
        let calls = Calls()
        var revisions = [Int](repeating: 0, count: 10)
        update(&layout, revisions: revisions, calls: calls)
        revisions[4] = 1
        revisions.removeLast(2)
        update(&layout, revisions: revisions, calls: calls)
        #expect(layout.rowCount == flat(revisions).count)
        #expect(window(&layout, 0 ..< layout.rowCount, revisions: revisions, calls: calls) == flat(revisions))
    }

    @Test func `empty items take no rows and are not laid out for the window`() {
        var layout = WindowedLayout<String>(margin: 0)
        let calls = Calls()
        layout.update(width: 10, revisions: [0, 0, 0], keepingFromEnd: 0) { $0 == 1 ? [] : ["item \($0)"] }
        #expect(layout.rowCount == 2)
        let shown = layout.lines(in: 0 ..< 2) { item in
            calls.items.append(item)
            return item == 1 ? [] : ["item \(item)"]
        }
        #expect(shown == ["item 0", "item 2"])
        #expect(calls.items == [0, 2])
        #expect(layout.item(atRow: 1) == 2)
    }

    @Test func `a new width lays everything out again`() {
        var layout = WindowedLayout<String>()
        let calls = Calls()
        update(&layout, revisions: [0, 0, 0], calls: calls)
        calls.items = []
        update(&layout, width: 20, revisions: [0, 0, 0], calls: calls)
        #expect(calls.items == [2, 1, 0])
    }
}
