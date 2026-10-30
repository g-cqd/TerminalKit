import Testing

@testable import TerminalKitText

/// An item that changes far above the end (a block unfolded at the top of a long conversation) costs its own layout, not the layout of
/// every item after it: ask's roadmap 0158 measured seconds for one click on a long session.
@Suite("A changed item is laid out alone")
struct WindowedLayoutChangeTests {
    private final class Calls {
        var items: [Int] = []
    }

    /// Item `n` at revision `r` lays out to `(n + r) % 3 + 1` lines, so a new revision can change its height.
    private static func lines(of item: Int, revision: Int) -> [String] {
        (0 ..< (item + revision) % 3 + 1).map { "item \(item) rev \(revision) line \($0)" }
    }

    private func layout(_ revisions: [Int], calls: Calls) -> (Int) -> [String] {
        { item in
            calls.items.append(item)
            return Self.lines(of: item, revision: revisions[item])
        }
    }

    private func flat(_ revisions: [Int]) -> [String] {
        revisions.indices.flatMap { Self.lines(of: $0, revision: revisions[$0]) }
    }

    @Test func `changing an item near the top lays out that item only, and the window is right`() {
        var revisions = Array(repeating: 0, count: 2_000)
        var windowed = WindowedLayout<String>()
        let calls = Calls()
        windowed.update(width: 10, revisions: revisions, keepingFromEnd: 20, layout: layout(revisions, calls: calls))
        let total = flat(revisions).count
        // Scrolled to the top: every item is known.
        _ = windowed.lines(fromEnd: total - 20, rows: 20, layout: layout(revisions, calls: calls))
        #expect(windowed.isComplete)
        revisions[3] = 1
        calls.items = []
        windowed.update(width: 10, revisions: revisions, keepingFromEnd: 20, layout: layout(revisions, calls: calls))
        let all = flat(revisions)
        let shown = windowed.lines(fromEnd: all.count - 20, rows: 20, layout: layout(revisions, calls: calls))
        #expect(Set(calls.items).count <= 10, "laid out again: \(Set(calls.items).sorted().prefix(20))")
        #expect(calls.items.contains(3))
        #expect(shown == Array(all[0 ..< 20]))
        #expect(windowed.rowCount == all.count)
        #expect(windowed.lines(fromEnd: 0, rows: 5, layout: layout(revisions, calls: calls)) == Array(all.suffix(5)))
    }

    @Test func `several changes, one before what is known, and a shorter document all stay right`() {
        var revisions = Array(repeating: 0, count: 300)
        var windowed = WindowedLayout<String>()
        let calls = Calls()
        windowed.update(width: 10, revisions: revisions, keepingFromEnd: 30, layout: layout(revisions, calls: calls))
        _ = windowed.lines(fromEnd: 100, rows: 20, layout: layout(revisions, calls: calls))
        revisions[2] = 4  // not known yet
        revisions[250] = 2
        revisions[299] = 1
        windowed.update(width: 10, revisions: revisions, keepingFromEnd: 30, layout: layout(revisions, calls: calls))
        var all = flat(revisions)
        #expect(windowed.lines(fromEnd: 0, rows: 40, layout: layout(revisions, calls: calls)) == Array(all.suffix(40)))
        #expect(
            windowed.lines(fromEnd: all.count - 10, rows: 10, layout: layout(revisions, calls: calls))
                == Array(all[0 ..< 10]))
        revisions.removeLast(50)
        windowed.update(width: 10, revisions: revisions, keepingFromEnd: 30, layout: layout(revisions, calls: calls))
        all = flat(revisions)
        #expect(windowed.lines(fromEnd: 0, rows: 40, layout: layout(revisions, calls: calls)) == Array(all.suffix(40)))
    }
}
