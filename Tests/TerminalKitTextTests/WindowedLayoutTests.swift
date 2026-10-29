import Testing

@testable import TerminalKitText

/// A long document laid out from its end, of which only the rows near the window are built (roadmap 0023).
@Suite("A windowed layout builds only the rows near the window, from the end")
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
        _ layout: inout WindowedLayout<String>, fromEnd: Int, rows: Int, revisions: [Int], calls: Calls
    ) -> [String] {
        layout.lines(fromEnd: fromEnd, rows: rows) { item in
            calls.items.append(item)
            return Self.lines(of: item, revision: revisions[item])
        }
    }

    /// Every line of the document end to end, as ``LayoutCache`` would hold it.
    private func flat(_ revisions: [Int]) -> [String] {
        revisions.indices.flatMap { Self.lines(of: $0, revision: revisions[$0]) }
    }

    @Test func `opening lays out only the items the end's rows need`() {
        var layout = WindowedLayout<String>()
        let calls = Calls()
        update(&layout, revisions: [Int](repeating: 0, count: 1_000), keeping: 5, calls: calls)
        // Items 999 (1 row), 998 (3 rows) and 997 (2 rows) cover the last 5 rows.
        #expect(calls.items == [999, 998, 997])
        #expect(layout.rowCount == 6 && layout.firstKnown == 997 && !layout.isComplete)
        #expect(layout.heldItems == [997, 998, 999])
    }

    @Test func `a window anywhere shows the same lines as the whole document`() {
        let revisions = [Int](repeating: 0, count: 50)
        let all = flat(revisions)
        for (fromEnd, rows) in [(0, 7), (13, 18), (all.count - 6, 6), (all.count - 3, 10), (all.count + 5, 4)] {
            var layout = WindowedLayout<String>()
            let calls = Calls()
            update(&layout, revisions: revisions, keeping: 3, calls: calls)
            let end = Swift.max(0, all.count - fromEnd)
            let expected = Array(all[Swift.max(0, end - rows) ..< end])
            #expect(window(&layout, fromEnd: fromEnd, rows: rows, revisions: revisions, calls: calls) == expected)
        }
    }

    @Test func `scrolling up reaches further items, and the whole document is known at the top`() {
        var layout = WindowedLayout<String>(margin: 0)
        let calls = Calls()
        let revisions = [Int](repeating: 0, count: 30)
        update(&layout, revisions: revisions, keeping: 4, calls: calls)
        let before = layout.rowCount
        _ = window(&layout, fromEnd: 10, rows: 4, revisions: revisions, calls: calls)
        #expect(layout.rowCount >= 14 && layout.rowCount > before)
        _ = window(&layout, fromEnd: 1_000, rows: 4, revisions: revisions, calls: calls)
        #expect(layout.isComplete && layout.rowCount == flat(revisions).count)
    }

    @Test func `the window keeps what it shows between frames and lets far items go`() {
        var layout = WindowedLayout<String>(margin: 0)
        let calls = Calls()
        let revisions = [Int](repeating: 0, count: 50)
        update(&layout, revisions: revisions, keeping: 3, calls: calls)
        _ = window(&layout, fromEnd: 20, rows: 4, revisions: revisions, calls: calls)
        let shown = layout.heldItems
        #expect(!shown.contains(49), "the end's items are let go once out of reach")
        calls.items = []
        _ = window(&layout, fromEnd: 20, rows: 4, revisions: revisions, calls: calls)
        #expect(calls.items.isEmpty && layout.heldItems == shown, "kept between frames")
    }

    @Test func `streaming the last item lays out only that item`() {
        var layout = WindowedLayout<String>()
        let calls = Calls()
        var revisions = [Int](repeating: 0, count: 40)
        update(&layout, revisions: revisions, keeping: 10, calls: calls)
        _ = window(&layout, fromEnd: 0, rows: 10, revisions: revisions, calls: calls)
        calls.items = []
        revisions[39] = 1
        update(&layout, revisions: revisions, keeping: 10, calls: calls)
        let shown = window(&layout, fromEnd: 0, rows: 10, revisions: revisions, calls: calls)
        #expect(calls.items == [39])
        #expect(shown.last == "item 39 rev 1 line 0")
    }

    @Test func `an item appended after known rows is laid out at once`() {
        var layout = WindowedLayout<String>()
        let calls = Calls()
        var revisions = [Int](repeating: 0, count: 10)
        update(&layout, revisions: revisions, keeping: 4, calls: calls)
        calls.items = []
        revisions += [0, 0]
        update(&layout, revisions: revisions, keeping: 4, calls: calls)
        #expect(calls.items.prefix(2) == [11, 10])
        #expect(
            window(&layout, fromEnd: 0, rows: 6, revisions: revisions, calls: calls) == Array(flat(revisions).suffix(6))
        )
    }

    @Test func `a changed item in the middle moves the rows after it, and removed items go`() {
        var layout = WindowedLayout<String>()
        let calls = Calls()
        var revisions = [Int](repeating: 0, count: 10)
        update(&layout, revisions: revisions, keeping: 100, calls: calls)
        revisions[4] = 1
        revisions.removeLast(2)
        update(&layout, revisions: revisions, keeping: 100, calls: calls)
        #expect(layout.isComplete && layout.rowCount == flat(revisions).count)
        #expect(
            window(&layout, fromEnd: 0, rows: layout.rowCount, revisions: revisions, calls: calls) == flat(revisions))
    }

    @Test func `a document cut below what was known starts again from its end`() {
        var layout = WindowedLayout<String>()
        let calls = Calls()
        update(&layout, revisions: [Int](repeating: 0, count: 100), keeping: 3, calls: calls)
        calls.items = []
        let shorter = [Int](repeating: 0, count: 20)
        update(&layout, revisions: shorter, keeping: 3, calls: calls)
        #expect(calls.items == [19, 18])
        #expect(
            window(&layout, fromEnd: 0, rows: 3, revisions: shorter, calls: calls) == Array(flat(shorter).suffix(3)))
    }

    @Test func `empty items take no rows`() {
        var layout = WindowedLayout<String>(margin: 0)
        let layoutOf: (Int) -> [String] = { $0 == 1 ? [] : ["item \($0)"] }
        layout.update(width: 10, revisions: [0, 0, 0], keepingFromEnd: 10, layout: layoutOf)
        #expect(layout.rowCount == 2 && layout.isComplete)
        #expect(layout.lines(fromEnd: 0, rows: 2, layout: layoutOf) == ["item 0", "item 2"])
    }

    /// A fixed sequence, so a failure repeats.
    private struct SplitMix: RandomNumberGenerator {
        var state: UInt64
        mutating func next() -> UInt64 {
            state &+= 0x9E37_79B9_7F4A_7C15
            var value = state
            value = (value ^ (value >> 30)) &* 0xBF58_476D_1CE4_E5B9
            value = (value ^ (value >> 27)) &* 0x94D0_49BB_1331_11EB
            return value ^ (value >> 31)
        }
    }

    /// Edits, appends, cuts, new widths and windows at random: every window equals the same rows of the whole document.
    @Test func `random edits and windows agree with the whole document`() {
        var random = SplitMix(state: 42)
        var layout = WindowedLayout<String>()
        var revisions = [Int](repeating: 0, count: 60)
        var width = 10
        for _ in 0 ..< 2_000 {
            switch Int.random(in: 0 ..< 10, using: &random) {
                case 0: revisions.append(0)
                case 1 where !revisions.isEmpty: revisions[Int.random(in: 0 ..< revisions.count, using: &random)] += 1
                case 2 where revisions.count > 5: revisions.removeLast(Int.random(in: 1 ... 5, using: &random))
                case 3: width = Int.random(in: 8 ... 12, using: &random)
                case 4: layout.margin = Bool.random(using: &random) ? nil : Int.random(in: 0 ... 5, using: &random)
                default: break
            }
            let rows = Int.random(in: 1 ... 12, using: &random)
            let fromEnd = Int.random(in: 0 ... 140, using: &random)
            let lines = { (item: Int) in Self.lines(of: item, revision: revisions[item]) }
            layout.update(width: width, revisions: revisions, keepingFromEnd: fromEnd + 2 * rows, layout: lines)
            let all = flat(revisions)
            let end = Swift.max(0, all.count - fromEnd)
            #expect(
                layout.lines(fromEnd: fromEnd, rows: rows, layout: lines)
                    == Array(all[Swift.max(0, end - rows) ..< end]))
            #expect(layout.rowCount <= all.count && (!layout.isComplete || layout.rowCount == all.count))
        }
    }

    @Test func `a new width forgets every height and lays out from the end`() {
        var layout = WindowedLayout<String>()
        let calls = Calls()
        update(&layout, revisions: [Int](repeating: 0, count: 100), keeping: 100, calls: calls)
        calls.items = []
        update(&layout, width: 20, revisions: [Int](repeating: 0, count: 100), keeping: 3, calls: calls)
        #expect(calls.items == [99, 98])
    }
}
