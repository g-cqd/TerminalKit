import Testing

@testable import TerminalKitText

/// A growing document laid out item by item: only items from the first changed one onward are laid out again.
@Suite("A layout cache lays out only what changed")
struct LayoutCacheTests {
    private final class Calls {
        var items: [Int] = []
    }

    private func update(
        _ cache: inout LayoutCache<String>, width: Int = 10, revisions: [Int], calls: Calls
    ) {
        cache.update(width: width, revisions: revisions) { item in
            calls.items.append(item)
            return ["item \(item) rev \(revisions[item])", "item \(item) tail"]
        }
    }

    @Test func `the first update lays out every item, end to end`() {
        var cache = LayoutCache<String>()
        let calls = Calls()

        update(&cache, revisions: [0, 0, 0], calls: calls)

        #expect(calls.items == [0, 1, 2])
        #expect(cache.lines.count == 6)
        #expect(cache.lines[2] == "item 1 rev 0")
    }

    @Test func `nothing changed lays out nothing`() {
        var cache = LayoutCache<String>()
        let calls = Calls()
        update(&cache, revisions: [0, 0, 0], calls: calls)
        calls.items = []

        update(&cache, revisions: [0, 0, 0], calls: calls)

        #expect(calls.items.isEmpty)
        #expect(cache.lines.count == 6)
    }

    @Test func `a new item is the only one laid out`() {
        var cache = LayoutCache<String>()
        let calls = Calls()
        update(&cache, revisions: [0, 0], calls: calls)
        calls.items = []

        update(&cache, revisions: [0, 0, 0], calls: calls)

        #expect(calls.items == [2])
        #expect(cache.lines.count == 6)
    }

    @Test func `a changed item and everything after it are laid out again`() {
        var cache = LayoutCache<String>()
        let calls = Calls()
        update(&cache, revisions: [0, 0, 0, 0], calls: calls)
        calls.items = []

        update(&cache, revisions: [0, 1, 0, 0], calls: calls)

        #expect(calls.items == [1, 2, 3])
        #expect(cache.lines[2] == "item 1 rev 1")
        #expect(cache.lines.count == 8)
    }

    @Test func `a streamed last item is the only one laid out`() {
        var cache = LayoutCache<String>()
        let calls = Calls()
        update(&cache, revisions: [0, 0, 0], calls: calls)
        calls.items = []

        update(&cache, revisions: [0, 0, 1], calls: calls)

        #expect(calls.items == [2])
    }

    @Test func `a new width lays out everything`() {
        var cache = LayoutCache<String>()
        let calls = Calls()
        update(&cache, width: 10, revisions: [0, 0], calls: calls)
        calls.items = []

        update(&cache, width: 20, revisions: [0, 0], calls: calls)

        #expect(calls.items == [0, 1])
    }

    @Test func `fewer items than before drops the lines of the ones gone`() {
        var cache = LayoutCache<String>()
        let calls = Calls()
        update(&cache, revisions: [0, 0, 0], calls: calls)
        calls.items = []

        update(&cache, revisions: [0, 0], calls: calls)

        #expect(calls.items.isEmpty)
        #expect(cache.lines.count == 4)
    }

    @Test func `an emptied document has no lines`() {
        var cache = LayoutCache<String>()
        let calls = Calls()
        update(&cache, revisions: [0, 0], calls: calls)

        update(&cache, revisions: [], calls: calls)

        #expect(cache.lines.isEmpty)
    }

    @Test func `reset forgets every line`() {
        var cache = LayoutCache<String>()
        let calls = Calls()
        update(&cache, revisions: [0, 0], calls: calls)
        cache.reset()
        calls.items = []

        update(&cache, revisions: [0, 0], calls: calls)

        #expect(calls.items == [0, 1])
    }
}
