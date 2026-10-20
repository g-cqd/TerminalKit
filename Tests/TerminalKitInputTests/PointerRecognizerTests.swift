import Testing

@testable import TerminalKitCodecs
@testable import TerminalKitInput

private typealias Pointer = PointerEvent<String>

/// A zero-based region map the tests share: a header on row 0, a block on rows 2 to 4, and a popup over part of the block.
private func sampleRegions() -> RegionMap<String> {
    var regions = RegionMap<String>()
    regions.add("header", at: CellRect(row: 0, col: 0, rows: 1, cols: 80))
    regions.add("block", at: CellRect(row: 2, col: 0, rows: 3, cols: 80))
    regions.add("popup", at: CellRect(row: 3, col: 10, rows: 2, cols: 20), layer: 1)
    return regions
}

/// One-based, as the decoder produces it.
private func report(
    _ kind: MouseEventKind, _ button: MouseButton = .left, row: Int, col: Int, modifiers: KeyModifiers = []
) -> MouseEvent {
    MouseEvent(button: button, modifiers: modifiers, row: row, col: col, kind: kind)
}

private func run(
    _ steps: [(MouseEvent, Double)], in regions: RegionMap<String>,
    settings: PointerRecognizer<String>.Settings = .init()
)
    -> [Pointer]
{
    var recognizer = PointerRecognizer<String>(settings: settings)
    let start = ContinuousClock.now
    var out: [Pointer] = []
    for (event, seconds) in steps {
        recognizer.handle(event, at: start + .seconds(seconds), in: regions) { out.append($0) }
    }
    return out
}

@Suite("Regions find what is on top")
struct RegionMapTests {
    @Test func `a cell inside a region finds it, and a cell outside finds nothing`() {
        let regions = sampleRegions()
        #expect(regions.hit(row: 0, col: 5) == "header")
        #expect(regions.hit(row: 2, col: 0) == "block")
        #expect(regions.hit(row: 1, col: 5) == nil)
        #expect(regions.hit(row: 5, col: 5) == nil)
    }

    @Test func `the edges are inclusive of the first cell and exclusive of the one past the last`() {
        var regions = RegionMap<String>()
        regions.add("r", at: CellRect(row: 2, col: 3, rows: 2, cols: 4))
        #expect(regions.hit(row: 2, col: 3) == "r")
        #expect(regions.hit(row: 3, col: 6) == "r")
        #expect(regions.hit(row: 4, col: 3) == nil)
        #expect(regions.hit(row: 2, col: 7) == nil)
        #expect(regions.hit(row: 1, col: 3) == nil)
        #expect(regions.hit(row: 2, col: 2) == nil)
    }

    @Test func `a higher layer wins where regions overlap, and the later one wins a tie`() {
        let regions = sampleRegions()
        #expect(regions.hit(row: 3, col: 15) == "popup")
        #expect(regions.hit(row: 3, col: 5) == "block")
        var tie = RegionMap<String>()
        tie.add("first", at: CellRect(row: 0, col: 0, rows: 5, cols: 5))
        tie.add("second", at: CellRect(row: 0, col: 0, rows: 5, cols: 5))
        #expect(tie.hit(row: 1, col: 1) == "second")
    }

    @Test func `a region with no cells is ignored, and clearing keeps the map usable`() {
        var regions = RegionMap<String>()
        regions.add("empty", at: CellRect(row: 0, col: 0, rows: 0, cols: 10))
        #expect(regions.count == 0)
        regions.add("one", at: CellRect(row: 0, col: 0, rows: 1, cols: 1))
        regions.removeAll()
        #expect(regions.count == 0 && regions.hit(row: 0, col: 0) == nil)
    }
}

@Suite("The pointer recognizer turns reports into clicks, drags and wheel steps")
struct PointerRecognizerTests {
    @Test func `a press and a release on one cell is a click on the region, in zero-based cells`() {
        let events = run(
            [(report(.press, row: 3, col: 6), 0), (report(.release, row: 3, col: 6), 0.05)], in: sampleRegions())
        #expect(
            events == [
                .click(target: "block", cell: CellPosition(row: 2, col: 5), button: .left, modifiers: [], count: 1)
            ])
    }

    @Test func `a click over nothing is still reported, with no target`() {
        let events = run(
            [(report(.press, row: 2, col: 1), 0), (report(.release, row: 2, col: 1), 0.05)], in: sampleRegions())
        #expect(
            events == [.click(target: nil, cell: CellPosition(row: 1, col: 0), button: .left, modifiers: [], count: 1)])
    }

    @Test func `the modifiers held at the press are the click's`() {
        let events = run(
            [(report(.press, row: 1, col: 1, modifiers: [.alt]), 0), (report(.release, row: 1, col: 1), 0.05)],
            in: sampleRegions())
        #expect(
            events == [
                .click(target: "header", cell: CellPosition(row: 0, col: 0), button: .left, modifiers: [.alt], count: 1)
            ])
    }

    @Test func `a release elsewhere is a drag and not a click on either target`() {
        // Two rows of movement with no motion report is far enough to be a drag, so it is one.
        let events = run(
            [(report(.press, row: 1, col: 1), 0), (report(.release, row: 3, col: 1), 0.05)], in: sampleRegions())
        #expect(!events.contains { if case .click = $0 { true } else { false } })
    }

    @Test func `content that moves under a still pointer is not a click on what is there now`() {
        // The pointer never moves, but a scroll between the press and the release puts another region under it.
        var before = RegionMap<String>()
        before.add("first", at: CellRect(row: 0, col: 0, rows: 5, cols: 80))
        var after = RegionMap<String>()
        after.add("second", at: CellRect(row: 0, col: 0, rows: 5, cols: 80))
        var recognizer = PointerRecognizer<String>()
        var out: [Pointer] = []
        recognizer.handle(report(.press, row: 3, col: 6), at: .now, in: before) { out.append($0) }
        recognizer.handle(report(.release, row: 3, col: 6), at: .now, in: after) { out.append($0) }
        #expect(out.isEmpty)
        // The same gesture with the content still is a click, so the case above is the target check and nothing else.
        recognizer.handle(report(.press, row: 3, col: 6), at: .now, in: after) { out.append($0) }
        recognizer.handle(report(.release, row: 3, col: 6), at: .now, in: after) { out.append($0) }
        #expect(
            out == [
                .click(target: "second", cell: CellPosition(row: 2, col: 5), button: .left, modifiers: [], count: 1)
            ])
    }

    @Test func `motion past the threshold begins a drag once, then moves, then ends, and is never a click`() {
        let events = run(
            [
                (report(.press, row: 3, col: 1), 0), (report(.drag, row: 3, col: 1), 0.01),
                (report(.drag, row: 3, col: 2), 0.02),
                (report(.drag, row: 3, col: 3), 0.03), (report(.release, row: 3, col: 3), 0.04)
            ], in: sampleRegions())
        #expect(
            events == [
                .dragBegan(target: "block", origin: CellPosition(row: 2, col: 0), button: .left, modifiers: []),
                .dragMoved(to: CellPosition(row: 2, col: 1)), .dragMoved(to: CellPosition(row: 2, col: 2)),
                .dragEnded(at: CellPosition(row: 2, col: 2))
            ])
    }

    @Test func `a larger threshold keeps a small wobble a click`() {
        let events = run(
            [
                (report(.press, row: 3, col: 1), 0), (report(.drag, row: 3, col: 2), 0.01),
                (report(.release, row: 3, col: 1), 0.02)
            ], in: sampleRegions(), settings: .init(dragThreshold: 2))
        #expect(
            events == [
                .click(target: "block", cell: CellPosition(row: 2, col: 0), button: .left, modifiers: [], count: 1)
            ])
    }

    @Test func `a release far from the press with no motion reported is a drag, as with mode 1000 alone`() {
        let events = run(
            [(report(.press, row: 3, col: 1), 0), (report(.release, row: 3, col: 9), 0.05)], in: sampleRegions())
        #expect(
            events == [
                .dragBegan(target: "block", origin: CellPosition(row: 2, col: 0), button: .left, modifiers: []),
                .dragEnded(at: CellPosition(row: 2, col: 8))
            ])
    }

    @Test func `clicks in quick succession on one cell count as a double and a triple, then start over`() {
        func click(at seconds: Double) -> [(MouseEvent, Double)] {
            [(report(.press, row: 3, col: 6), seconds), (report(.release, row: 3, col: 6), seconds + 0.02)]
        }
        let events = run(click(at: 0) + click(at: 0.2) + click(at: 0.4) + click(at: 0.6), in: sampleRegions())
        let counts = events.compactMap { event -> Int? in
            if case .click(_, _, _, _, let count) = event { count } else { nil }
        }
        #expect(counts == [1, 2, 3, 1])
    }

    @Test func `a pause longer than the interval, or a different row, or another button, resets the count`() {
        func click(row: Int, button: MouseButton = .left, at seconds: Double) -> [(MouseEvent, Double)] {
            [
                (report(.press, button, row: row, col: 6), seconds),
                (report(.release, button, row: row, col: 6), seconds + 0.02)
            ]
        }
        let steps =
            click(row: 3, at: 0) + click(row: 3, at: 1.0) + click(row: 4, at: 1.2)
            + click(row: 4, button: .right, at: 1.4)
        let counts = run(steps, in: sampleRegions())
            .compactMap { event -> Int? in
                if case .click(_, _, _, _, let count) = event { count } else { nil }
            }
        #expect(counts == [1, 1, 1, 1])
    }

    @Test func `a wheel step reports its direction and target and does not disturb a press`() {
        let events = run(
            [
                (report(.press, row: 3, col: 6), 0), (report(.press, .scrollDown, row: 3, col: 6), 0.01),
                (report(.press, .scrollUp, row: 1, col: 1, modifiers: [.shift]), 0.02),
                (report(.release, row: 3, col: 6), 0.03)
            ], in: sampleRegions())
        #expect(
            events == [
                .wheel(target: "block", cell: CellPosition(row: 2, col: 5), direction: .down, modifiers: []),
                .wheel(target: "header", cell: CellPosition(row: 0, col: 0), direction: .up, modifiers: [.shift]),
                .click(target: "block", cell: CellPosition(row: 2, col: 5), button: .left, modifiers: [], count: 1)
            ])
    }

    @Test func `motion with no button is ignored, and so is a pixel-mode report that has no cell`() {
        let events = run(
            [
                (report(.motion, .release, row: 3, col: 6), 0),
                (MouseEvent(button: .left, row: 0, col: 0, pixelX: 40, pixelY: 20), 0.01)
            ], in: sampleRegions())
        #expect(events.isEmpty)
    }

    @Test func `a stray release or drag with nothing pressed does nothing`() {
        let events = run(
            [(report(.release, row: 3, col: 6), 0), (report(.drag, row: 3, col: 7), 0.01)], in: sampleRegions())
        #expect(events.isEmpty)
    }

    @Test func `reset forgets a press in progress`() {
        var recognizer = PointerRecognizer<String>()
        let regions = sampleRegions()
        recognizer.handle(report(.press, row: 3, col: 6), at: .now, in: regions) { _ in }
        #expect(recognizer.isPressed)
        recognizer.reset()
        #expect(!recognizer.isPressed)
    }
}
