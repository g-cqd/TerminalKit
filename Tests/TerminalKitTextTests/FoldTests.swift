import Testing

@testable import TerminalKitText

private func stack(_ heights: [(String, Int)]) -> BlockHeights<String> {
    var stack = BlockHeights<String>()
    for (id, height) in heights { stack.append(id, height: height) }
    return stack
}

@Suite("A block folds to its placeholder")
struct FoldableBlockTests {
    private let block = FoldableBlock(
        id: "code", lines: ["let a = 1", "let b = 2", "let c = 3"],
        placeholder: FoldPlaceholder(text: "swift, 3 lines", hint: "click to show"))

    @Test func `folded, it is its placeholder and one row; shown, it is its lines`() {
        #expect(block.visibleLines(folded: true) == ["swift, 3 lines"])
        #expect(block.visibleLines(folded: false) == ["let a = 1", "let b = 2", "let c = 3"])
        #expect(block.height(folded: true) == 1 && block.height(folded: false) == 3)
    }

    @Test func `a block with no lines is still one row, so it can be pointed at`() {
        let empty = FoldableBlock(id: "e", lines: [], placeholder: FoldPlaceholder(text: "empty"))
        #expect(empty.height(folded: false) == 1 && empty.height(folded: true) == 1)
    }

    @Test func `the placeholder always says something to read`() {
        // There is no initializer without a placeholder, so a block cannot fold to nothing; this checks what it carries.
        #expect(!block.placeholder.text.isEmpty && block.placeholder.hint == "click to show")
        #expect(FoldPlaceholder(text: "x").hint == nil)
    }
}

@Suite("Fold state is per block, with a default")
struct FoldStoreTests {
    @Test func `with no choice a block follows the default for its kind`() {
        let store = FoldStore<String>()
        #expect(store.isFolded("thinking", default: true))
        #expect(!store.isFolded("answer", default: false))
    }

    @Test func `toggling flips what the block is now, and remembers it`() {
        var store = FoldStore<String>()
        #expect(store.toggle("t", default: true) == false)  // was folded by default, now shown
        #expect(!store.isFolded("t", default: true))
        #expect(store.toggle("t", default: true) == true)  // and back
        #expect(store.chosenCount == 1)
    }

    @Test func `a choice survives a change of default, and a block without one follows it`() {
        var store = FoldStore<String>()
        store.set("chosen", folded: false)
        #expect(!store.isFolded("chosen", default: true) && !store.isFolded("chosen", default: false))
        #expect(store.isFolded("other", default: true) && !store.isFolded("other", default: false))
    }

    @Test func `clearing a choice, or all of them, returns to the defaults`() {
        var store = FoldStore<String>()
        store.set("a", folded: false)
        store.set("b", folded: false)
        store.clearChoice(for: "a")
        #expect(store.isFolded("a", default: true) && !store.isFolded("b", default: true))
        store.clearChoices()
        #expect(store.chosenCount == 0 && store.isFolded("b", default: true))
    }
}

@Suite("Folding a block does not move what the reader is reading")
struct ScrollAnchorTests {
    @Test func `the stack knows where each block starts and which block a row is in`() {
        let blocks = stack([("a", 3), ("b", 10), ("c", 4), ("d", 6)])
        #expect(blocks.rowCount == 23)
        #expect(blocks.firstRow(of: "c") == 13 && blocks.firstRow(of: "missing") == nil)
        #expect(blocks.anchor(atRow: 0) == ScrollAnchor(block: "a", rowInBlock: 0))
        #expect(blocks.anchor(atRow: 2) == ScrollAnchor(block: "a", rowInBlock: 2))
        #expect(blocks.anchor(atRow: 3) == ScrollAnchor(block: "b", rowInBlock: 0))
        #expect(blocks.anchor(atRow: 15) == ScrollAnchor(block: "c", rowInBlock: 2))
        #expect(blocks.anchor(atRow: 22) == ScrollAnchor(block: "d", rowInBlock: 5))
        #expect(blocks.anchor(atRow: 23) == nil && blocks.anchor(atRow: -1) == nil)
    }

    @Test func `folding a block above the viewport scrolls by exactly what it lost, so the text stays put`() throws {
        let before = stack([("a", 3), ("b", 10), ("c", 4), ("d", 6)])
        let anchor = try #require(before.anchor(atRow: 15))  // the first visible row, in block c
        let after = stack([("a", 3), ("b", 1), ("c", 4), ("d", 6)])  // b folded: 9 rows shorter
        #expect(after.scrollOffset(keeping: anchor, atScreenRow: 0, viewportRows: 8) == 6)
        // and unfolding it again returns to where we were
        let back = try #require(after.anchor(atRow: 6))
        #expect(before.scrollOffset(keeping: back, atScreenRow: 0, viewportRows: 8) == 15)
    }

    @Test func `the anchor can sit anywhere on screen, not only on the top row`() throws {
        let before = stack([("a", 3), ("b", 10), ("c", 4), ("d", 6)])
        let anchor = try #require(before.anchor(atRow: 17))  // block d, shown at screen row 2
        let after = stack([("a", 3), ("b", 1), ("c", 4), ("d", 6)])
        let offset = try #require(after.scrollOffset(keeping: anchor, atScreenRow: 2, viewportRows: 8))
        #expect(after.row(of: anchor)! - offset == 2)
    }

    @Test func `folding the block that holds the anchor puts the anchor on its placeholder`() throws {
        let before = stack([("a", 3), ("b", 10), ("c", 4)])
        let anchor = try #require(before.anchor(atRow: 10))  // block b, row 7
        let after = stack([("a", 3), ("b", 1), ("c", 4)])
        #expect(after.row(of: anchor) == 3)  // clamped to b's one row
        #expect(after.scrollOffset(keeping: anchor, atScreenRow: 0, viewportRows: 4) == 3)
    }

    @Test func `a change below the viewport does not move it`() throws {
        let before = stack([("a", 3), ("b", 10), ("c", 4), ("d", 6)])
        let anchor = try #require(before.anchor(atRow: 4))
        let after = stack([("a", 3), ("b", 10), ("c", 4), ("d", 1)])
        #expect(after.scrollOffset(keeping: anchor, atScreenRow: 0, viewportRows: 8) == 4)
    }

    @Test func `the offset never goes below the top or leaves blank space below the last row`() throws {
        let before = stack([("a", 3), ("b", 10), ("c", 4)])
        let anchor = try #require(before.anchor(atRow: 1))
        #expect(before.scrollOffset(keeping: anchor, atScreenRow: 5, viewportRows: 8) == 0)  // would be negative
        let late = try #require(before.anchor(atRow: 16))
        // 17 rows with 8 visible: the offset is at most 9
        #expect(before.scrollOffset(keeping: late, atScreenRow: 0, viewportRows: 8) == 9)
        #expect(before.scrollOffset(keeping: anchor, atScreenRow: 0, viewportRows: 40) == 0)  // everything fits
    }

    @Test func `an anchor whose block is gone has nowhere to be, and an empty stack has no anchor`() {
        let blocks = stack([("a", 3)])
        #expect(
            blocks.scrollOffset(keeping: ScrollAnchor(block: "gone", rowInBlock: 0), atScreenRow: 0, viewportRows: 4)
                == nil)
        #expect(BlockHeights<String>().anchor(atRow: 0) == nil)
    }

    @Test func `over many random stacks and folds the anchored row keeps its screen row unless it hit an end`() throws {
        var seed: UInt64 = 0x9E37_79B9_7F4A_7C15
        func next(_ bound: Int) -> Int {
            seed = seed &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            return Int((seed >> 33) % UInt64(bound))
        }
        for _ in 0 ..< 500 {
            let count = 2 + next(12)
            let heights = (0 ..< count).map { _ in 1 + next(15) }
            let viewport = 3 + next(12)
            let before = heights.enumerated()
                .reduce(into: BlockHeights<Int>()) { $0.append($1.offset, height: $1.element) }
            guard before.rowCount > viewport else { continue }
            let top = next(before.rowCount - viewport + 1)
            let screenRow = next(viewport)
            let anchor = try #require(before.anchor(atRow: top + screenRow))
            var folded = heights
            let which = next(count)
            // fold it, or open it if it was already one row
            folded[which] = folded[which] == 1 ? 1 + next(15) : 1
            let after = folded.enumerated()
                .reduce(into: BlockHeights<Int>()) { $0.append($1.offset, height: $1.element) }
            let offset = try #require(
                after.scrollOffset(keeping: anchor, atScreenRow: screenRow, viewportRows: viewport))
            let row = try #require(after.row(of: anchor))
            let wanted = row - screenRow
            let atTop = wanted < 0
            let atBottom = wanted > max(0, after.rowCount - viewport)
            if atTop || atBottom {
                #expect(offset == (atTop ? 0 : max(0, after.rowCount - viewport)))
            } else {
                #expect(row - offset == screenRow, "block \(which) of \(heights) changed to \(folded[which])")
            }
        }
    }
}
